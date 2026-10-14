'use strict';
const express = require('express');
const { MongoClient } = require('mongodb');
const client = require('prom-client');

const PORT = Number(process.env.PORT || 3000);
const { MONGO_USER = '', MONGO_PASSWORD = '', MONGO_HOST = 'mongodb', MONGO_DB = 'app' } = process.env;
const uri = `mongodb://${encodeURIComponent(MONGO_USER)}:${encodeURIComponent(MONGO_PASSWORD)}@${MONGO_HOST}:27017/${MONGO_DB}?authSource=admin`;

// ---- metrics ----
client.collectDefaultMetrics();
const httpDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2],
});

// ---- mongo (connect with retry; readiness reflects DB state) ----
const mongo = new MongoClient(uri, { serverSelectionTimeoutMS: 3000 });
let messages = null;
async function connectLoop() {
  for (;;) {
    try {
      await mongo.connect();
      messages = mongo.db(MONGO_DB).collection('messages');
      console.log(JSON.stringify({ level: 'info', msg: 'mongo connected' }));
      return;
    } catch (e) {
      console.error(JSON.stringify({ level: 'warn', msg: 'mongo unavailable, retrying', err: e.message }));
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '10kb' }));
app.use((req, res, next) => {
  const end = httpDuration.startTimer();
  res.on('finish', () => end({ method: req.method, route: req.route ? req.route.path : 'unmatched', status: res.statusCode }));
  next();
});

app.get('/healthz', (_req, res) => res.status(200).send('ok'));   // liveness
app.get('/readyz', async (_req, res) => {                          // readiness
  try {
    await mongo.db('admin').command({ ping: 1 });
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
  if (!messages) return res.status(503).json({ error: 'database not ready' });
  const docs = await messages.find({}, { projection: { _id: 0 } }).sort({ createdAt: -1 }).limit(50).toArray();
  res.json(docs);
});
app.post('/api/messages', async (req, res) => {
  const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
  if (!text || text.length > 280) return res.status(400).json({ error: 'text must be 1-280 chars' });
  if (!messages) return res.status(503).json({ error: 'database not ready' });
  const doc = { text, createdAt: new Date() };
  await messages.insertOne({ ...doc });
  res.status(201).json(doc);
});

const server = app.listen(PORT, () => console.log(JSON.stringify({ level: 'info', msg: `listening on ${PORT}` })));
connectLoop();

// graceful shutdown (Kubernetes sends SIGTERM)
process.on('SIGTERM', () => {
  server.close(async () => { await mongo.close(); process.exit(0); });
});
