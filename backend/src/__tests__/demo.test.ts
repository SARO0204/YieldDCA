import { describe, it, expect, vi, beforeEach } from 'vitest';
import request from 'supertest';
import { app } from '../server';

vi.mock('../services/demo.service', () => ({
  setupDemo: vi.fn().mockResolvedValue({ status: 'Demo setup initialized', strategyId: '1' }),
  stepDemo: vi.fn().mockResolvedValue({ status: 'Step advanced', state: 'DAY_0', simulatedDay: 0 }),
  getDemoStatus: vi.fn().mockResolvedValue({ state: 'INITIAL', simulatedDay: -1, strategyId: '1' }),
  resetDemo: vi.fn().mockResolvedValue({ status: 'Demo reset' }),
}));

describe('Demo API', () => {
  it('should initialize demo via /api/demo/setup', async () => {
    const res = await request(app)
      .post('/api/demo/setup')
      .send({ strategyId: '1' });
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('Demo setup initialized');
  });

  it('should fail setup if strategyId missing', async () => {
    const res = await request(app)
      .post('/api/demo/setup')
      .send({});
    expect(res.status).toBe(400);
  });

  it('should step demo via /api/demo/step', async () => {
    const res = await request(app).post('/api/demo/step');
    expect(res.status).toBe(200);
    expect(res.body.state).toBe('DAY_0');
  });

  it('should get demo status via /api/demo/status', async () => {
    const res = await request(app).get('/api/demo/status');
    expect(res.status).toBe(200);
    expect(res.body.state).toBe('INITIAL');
  });

  it('should reset demo via /api/demo/reset', async () => {
    const res = await request(app).post('/api/demo/reset');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('Demo reset');
  });
});
