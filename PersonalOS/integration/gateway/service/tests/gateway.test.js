const request = require("supertest");

const BASE_URL = process.env.TEST_BASE_URL || "http://localhost:8080";
const ADMIN_TOKEN = process.env.TEST_ADMIN_TOKEN || "devtoken";

describe("Gateway API Tests", () => {
    const agent = request.agent(BASE_URL);

    beforeAll(() => {
        agent.set("Authorization", `Bearer ${ADMIN_TOKEN}`);
    });

    describe("Health & Metrics", () => {
        it("GET /health should return ok", async () => {
            const res = await request(BASE_URL).get("/health");
            expect(res.status).toBe(200);
            expect(res.body.status).toBe("ok");
        });

        it("GET /metrics should return prometheus metrics", async () => {
            const res = await request(BASE_URL).get("/metrics");
            expect(res.status).toBe(200);
            expect(res.text).toContain("gateway_");
        });
    });

    describe("Session Management", () => {
        let testSessionId;

        it("POST /sessions/start should create a session", async () => {
            const res = await agent.post("/sessions/start").send({ meta: { test: true } });
            expect(res.status).toBe(200);
            expect(res.body.ok).toBe(true);
            expect(res.body.session).toHaveProperty("session_id");
            testSessionId = res.body.session.session_id;
        });

        it("GET /sessions/:session_id should retrieve session", async () => {
            const res = await agent.get(`/sessions/${testSessionId}`);
            expect(res.status).toBe(200);
            expect(res.body.session.session_id).toBe(testSessionId);
        });

        it("GET /sessions/:session_id should return 404 for invalid session", async () => {
            const res = await agent.get("/sessions/invalid-session-123");
            expect(res.status).toBe(404);
        });
    });

    describe("Agent Invocation", () => {
        it("POST /invoke/:agent_id should invoke agent", async () => {
            const res = await agent.post("/invoke/test-agent").send({
                input: { message: "test" }
            });
            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty("ok");
        });

        it("POST /invoke/:agent_id with session_id should track analytics", async () => {
            const startSession = await agent.post("/sessions/start");
            const sessionId = startSession.body.session.session_id;

            const res = await agent.post("/invoke/test-agent").send({
                session_id: sessionId,
                input: { test: true }
            });

            expect(res.status).toBe(200);

            const analytics = await agent.get(`/analytics/${sessionId}`);
            expect(analytics.body.analytics.invocations).toBe("1");
        });

        it("POST /invoke/:agent_id should respect idempotency key", async () => {
            const startSession = await agent.post("/sessions/start");
            const sessionId = startSession.body.session.session_id;

            const idemKey = `test-idempotency-${Date.now()}`;

            const res1 = await agent
                .post("/invoke/test-agent")
                .set("X-Idempotency-Key", idemKey)
                .send({ session_id: sessionId, input: { test: true } });

            const res2 = await agent
                .post("/invoke/test-agent")
                .set("X-Idempotency-Key", idemKey)
                .send({ session_id: sessionId, input: { test: true } });

            expect(res1.status).toBe(200);
            expect(res2.status).toBe(200);
        });
    });

    describe("Webhook", () => {
        it("POST /webhook/:webhook_id should receive webhook", async () => {
            const res = await agent.post("/webhook/test-webhook").send({
                event: "test.event",
                data: { message: "hello" }
            });
            expect(res.status).toBe(200);
            expect(res.body.received).toBe(true);
        });

        it("POST /webhook with session_id should track analytics", async () => {
            const startSession = await agent.post("/sessions/start");
            const sessionId = startSession.body.session.session_id;

            await agent.post("/webhook/test-webhook").send({
                session_id: sessionId,
                event: "test.event"
            });

            const analytics = await agent.get(`/analytics/${sessionId}`);
            expect(analytics.body.analytics.webhooks_received).toBe("1");
        });

        it("GET /webhook/:webhook_id/events should list events", async () => {
            const res = await agent.get("/webhook/test-webhook/events");
            expect(res.status).toBe(200);
            expect(Array.isArray(res.body.events)).toBe(true);
        });
    });

    describe("Analytics", () => {
        it("POST /analytics/track should track custom event", async () => {
            const startSession = await agent.post("/sessions/start");
            const sessionId = startSession.body.session.session_id;

            const res = await agent.post("/analytics/track").send({
                session_id: sessionId,
                event: "custom_event",
                data: { value: 123 }
            });

            expect(res.status).toBe(200);
        });

        it("GET /analytics/:session_id should return analytics", async () => {
            const startSession = await agent.post("/sessions/start");
            const sessionId = startSession.body.session.session_id;

            await agent.post("/analytics/track").send({
                session_id: sessionId,
                event: "test"
            });

            const res = await agent.get(`/analytics/${sessionId}`);
            expect(res.status).toBe(200);
            expect(res.body.analytics).toHaveProperty("test");
        });
    });

    describe("Rate Limiting", () => {
        it("should return 429 when rate limit exceeded", async () => {
            const promises = [];
            for (let i = 0; i < 35; i++) {
                promises.push(
                    agent.post("/invoke/rate-test-agent").send({ input: {} })
                );
            }
            const results = await Promise.all(promises);
            const tooManyRequests = results.filter(r => r.status === 429);
            expect(tooManyRequests.length).toBeGreaterThan(0);
        }, 30000);
    });
});
