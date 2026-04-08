# Code Review Addons — Node.js / Express

## Security
- [ ] All user input validated with express-validator or joi
- [ ] Helmet middleware applied for security headers
- [ ] CORS configured restrictively (not `origin: *`)
- [ ] Rate limiting on auth endpoints (express-rate-limit)
- [ ] No `eval()` or `new Function()` with user input
- [ ] SQL queries use parameterized statements (no string concatenation)

## Express Patterns
- [ ] Async route handlers wrapped with error-catching middleware
- [ ] Business logic in services/ (routes are thin)
- [ ] Middleware applied in correct order (auth before business logic)
- [ ] Response format consistent (standard JSON structure)
- [ ] HTTP status codes used correctly (201 for create, 204 for delete, etc.)

## Database (Prisma/Sequelize/Knex)
- [ ] Eager loading used to prevent N+1 queries (`include` / `with`)
- [ ] Transactions for multi-step operations
- [ ] Migrations are idempotent
- [ ] Indexes on frequently-queried columns

## Node.js
- [ ] No synchronous filesystem operations in request handlers
- [ ] `Promise.all()` for independent async operations
- [ ] Proper error propagation (no swallowed errors)
- [ ] No `console.log` in production code (use structured logger)
