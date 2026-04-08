# Code Review Addons — Python / Django

## Security
- [ ] All views require authentication (LoginRequiredMixin or @login_required)
- [ ] CSRF protection enabled on all forms
- [ ] No raw SQL queries (use ORM or parameterized queries)
- [ ] User input validated with Django forms or serializers
- [ ] No `eval()` or `exec()` with user data
- [ ] SECRET_KEY not hardcoded

## Django Patterns
- [ ] Business logic in services.py or models (not views)
- [ ] QuerySets evaluated lazily (no premature `.all()`)
- [ ] `select_related()` / `prefetch_related()` for related objects
- [ ] Migrations squashed periodically
- [ ] Custom managers for complex queries

## DRF (if applicable)
- [ ] Serializers validate all input
- [ ] ViewSets use proper permissions (IsAuthenticated, custom)
- [ ] Pagination on list endpoints
- [ ] Throttling configured per endpoint

## Python
- [ ] Type hints on function signatures
- [ ] No bare `except:` clauses (catch specific exceptions)
- [ ] No `print()` in production code (use logging module)
- [ ] f-strings preferred over .format() or %
