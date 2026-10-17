'use strict';
const express = require('express');
const { MongoClient } = require('mongodb');
const client = require('prom-client');

const PORT = Number(process.env.PORT || 3000);
const { MONGO_USER = '', MONGO_PASSWORD = '', MONGO_HOST = 'mongodb', MONGO_DB = 'app' } = process.env;
const uri = `mongodb://${encodeURIComponent(MONGO_USER)}:${encodeURIComponent(MONGO_PASSWORD)}@${MONGO_HOST}:27017/${MONGO_DB}?authSource=admin`;
client.collectDefaultMetrics();
const httpDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2],
});

// ---- mongo: resilient client with auto-reconnect on failure ----
let mongoClient = null;
let isConnecting = null;

async function getClient() {
  if (mongoClient) {
    return mongoClient;
  }
  if (isConnecting) return isConnecting;
  
  isConnecting = (async () => {
    try {
      const client = new MongoClient(uri, { serverSelectionTimeoutMS: 3000 });
      await client.connect();
      mongoClient = client;
      return mongoClient;
    } finally {
      isConnecting = null;
    }
  })();

  return isConnecting;
}

const getMessagesCol = async () => {
  const c = await getClient();
  return c.db(MONGO_DB).collection('messages');
};

getClient().catch((err) => {
  console.error(JSON.stringify({ level: 'warn', msg: 'initial mongo connect pending', err: err.message }));
});

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '10kb' }));
app.use((req, res, next) => {
  const end = httpDuration.startTimer();
  res.on('finish', () => end({ method: req.method, route: req.route ? req.route.path : 'unmatched', status: res.statusCode }));
  next();
});

app.get('/healthz', (_req, res) => res.status(200).send('ok'));   // liveness
app.get('/readyz', async (_req, res) => {
  try {
    const c = await getClient();
    await c.db(MONGO_DB).command({ ping: 1 });
    res.status(200).send('ready');
  } catch {
    res.status(503).send('mongo not ready');
  }
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.send(await client.register.metrics());
});

app.get('/api/messages', async (_req, res) => {
  try {
    const col = await getMessagesCol();
    const docs = await col.find({}, { projection: { _id: 0 } }).sort({ createdAt: -1 }).limit(50).toArray();
    res.json(docs);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', msg: 'read failed', err: e.message }));
    res.status(503).json({ error: 'database not ready' });
  }
});
app.post('/api/messages', async (req, res) => {
  const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
  if (!text || text.length > 280) return res.status(400).json({ error: 'text must be 1-280 chars' });
  const doc = { text, createdAt: new Date() };
  try {
    const col = await getMessagesCol();
    await col.insertOne({ ...doc });
    res.status(201).json(doc);
  } catch (e) {
    console.error(JSON.stringify({ level: 'error', msg: 'write failed', err: e.message }));
    res.status(503).json({ error: 'database not ready' });
  }
});

const server = app.listen(PORT, () => console.log(JSON.stringify({ level: 'info', msg: `listening on ${PORT}` })));

// graceful shutdown (Kubernetes sends SIGTERM)
process.on('SIGTERM', () => {
  server.close(async () => {
    if (mongoClient) await mongoClient.close().catch(() => {});
    process.exit(0);
  });
});
