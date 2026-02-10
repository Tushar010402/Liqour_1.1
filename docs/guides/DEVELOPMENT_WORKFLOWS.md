# OCR Development Workflows

**Purpose**: Standard workflows for common development scenarios
**Audience**: All developers
**Last Updated**: January 15, 2025

---

## 📑 Table of Contents

1. [Daily Development Workflow](#daily-development-workflow)
2. [Feature Development Workflow](#feature-development-workflow)
3. [Bug Fix Workflow](#bug-fix-workflow)
4. [Code Review Workflow](#code-review-workflow)
5. [Deployment Workflow](#deployment-workflow)
6. [Incident Response Workflow](#incident-response-workflow)
7. [Onboarding Workflow](#onboarding-workflow)

---

## 1. Daily Development Workflow

### Morning Routine (10 minutes)

```bash
# 1. Start your day
cd /var/www/liquorpro

# 2. Check system status
./scripts/verify_deployment.sh | tail -10

# 3. Check overnight logs for errors
sudo docker logs liquorpro-sales-prod --since 12h | grep -i error | wc -l

# 4. If > 10 errors, investigate
sudo docker logs liquorpro-sales-prod --since 12h | grep -i error | head -20

# 5. Check recent changes
git log --since="yesterday" --oneline

# 6. Check for updates
git pull origin main

# 7. Review your tasks for the day
cat TODO.md  # Or your task tracker
```

### During Development

```mermaid
Start Development
       ↓
Create/Switch Branch
       ↓
Write Code (small increments)
       ↓
Run Tests Frequently ←───┐
       ↓                 │
Tests Pass?              │
  No ──────────────────→ Fix
  Yes
       ↓
Commit (small, focused)
       ↓
More work? ─Yes─→ Loop back to Write Code
  No
       ↓
Push & Create PR
```

**Best Practices**:
- Commit frequently (every 30-60 min)
- Run tests before each commit
- Write descriptive commit messages
- Keep changes small and focused

### End of Day (5 minutes)

```bash
# 1. Commit or stash work in progress
git status
git add .
git commit -m "WIP: [description]" || git stash

# 2. Push to backup your work
git push origin your-branch

# 3. Update TODO for tomorrow
echo "Tomorrow: [tasks]" >> TODO.md

# 4. Quick health check
docker ps | grep sales
```

---

## 2. Feature Development Workflow

### Phase 1: Planning (30-60 minutes)

```
1. Understand the requirement
   └─> Read feature request/ticket
   └─> Ask clarifying questions
   └─> Review related code

2. Design the approach
   └─> Sketch out solution
   └─> Identify files to modify
   └─> Consider edge cases

3. Plan testing strategy
   └─> What to test?
   └─> How to test?
   └─> Test data needed?

4. Review similar implementations
   └─> Check REAL_WORLD_EXAMPLES.md
   └─> Look for similar features in codebase
```

### Phase 2: Implementation (varies)

**Step 1: Create Branch**
```bash
git checkout -b feature/your-feature-name
```

**Step 2: Write Tests First (TDD approach)**
```go
// Write failing tests
func TestNewFeature(t *testing.T) {
    // Test code
}
```

```bash
# Run tests (should fail)
go test -run TestNewFeature ./internal/sales/services
```

**Step 3: Implement Feature**
```go
// Implement the feature
func NewFeature() {
    // Implementation
}
```

**Step 4: Make Tests Pass**
```bash
# Run tests repeatedly
go test -run TestNewFeature ./internal/sales/services

# Once passing, run all tests
go test ./internal/sales/services
```

**Step 5: Refactor & Optimize**
```go
// Improve code quality
// Remove duplication
// Add comments
```

**Step 6: Self-Review**
```bash
# Use checklist
cat CODE_REVIEW_CHECKLIST.md

# Check for common pitfalls
cat COMMON_PITFALLS.md

# Verify best practices
cat BEST_PRACTICES.md
```

### Phase 3: Documentation (15-30 minutes)

```markdown
1. Update code comments
2. Update CHANGELOG.md
3. Update relevant docs
4. Add examples if applicable
```

### Phase 4: PR Creation (15 minutes)

```bash
# 1. Commit all changes
git add .
git commit -m "feat: Add [feature description]"

# 2. Push branch
git push origin feature/your-feature-name

# 3. Create PR using template
# (Use TEMPLATES_PACKAGE.md → Pull Request Template)

# 4. Self-review on GitHub
# - Check diff
# - Add comments on complex parts
# - Verify all files included
```

### Phase 5: Address Review Comments

```
For each comment:
  1. Read carefully
  2. Ask questions if unclear
  3. Make requested changes
  4. Respond to comment
  5. Mark as resolved

After all addressed:
  └─> Re-request review
```

### Phase 6: Merge & Deploy

```bash
# 1. Squash commits if needed
git rebase -i main

# 2. Merge (after approval)
# (Usually done via GitHub)

# 3. Deploy
# (Follow Deployment Workflow)

# 4. Monitor
./scripts/ocr_metrics_monitor.sh 30
```

---

## 3. Bug Fix Workflow

### Step 1: Reproduce (30-60 minutes)

```
1. Gather information
   - User report
   - Error logs
   - Screenshots

2. Create reproduction
   └─> Write failing test
   └─> Document steps to reproduce

3. Verify bug exists
   └─> Run test (should fail)
   └─> Confirm in production logs
```

**Example**:
```bash
# Get logs
sudo docker logs liquorpro-sales-prod --since 1h | grep "BugSymptom"

# Write test
cat > bug_reproduction_test.go << 'EOF'
func TestBug_Reproduction(t *testing.T) {
    // Steps that trigger bug
    result := FunctionWithBug("input that breaks")

    // This should pass but currently fails
    if result != "expected" {
        t.Errorf("Bug present: got %v", result)
    }
}
EOF

# Run test (should fail, confirming bug)
go test -run TestBug_Reproduction
```

### Step 2: Investigate (varies)

```
1. Add debug logging
   └─> Temporary logging to understand flow

2. Use debugger (if available)
   └─> Set breakpoints
   └─> Step through code

3. Check related code
   └─> Where does the data come from?
   └─> Where does it go?

4. Form hypothesis
   └─> What do you think is wrong?
   └─> How can you verify?
```

**Investigation Tools**:
```bash
# Add temporary logging
fmt.Printf("DEBUG: value = %+v\n", value)

# Run with verbose logs
go test -v -run TestBug_Reproduction

# Check production behavior
sudo docker logs liquorpro-sales-prod | grep "Related pattern"
```

### Step 3: Fix (varies)

```
1. Write the fix
   └─> Minimal change to solve issue
   └─> Don't fix unrelated issues

2. Verify test passes
   └─> Run reproduction test
   └─> Should now pass

3. Run full test suite
   └─> Ensure no regressions
```

### Step 4: Add Regression Test

```go
// Add permanent test to prevent future regression
func TestBug_[IssueNumber]_NoRegression(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        // Case that was broken
        {"Original bug case", "problematic input", "correct output"},
        // Related edge cases
        {"Similar case 1", "input1", "output1"},
        {"Similar case 2", "input2", "output2"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := FixedFunction(tt.input)
            if result != tt.expected {
                t.Errorf("Regression! Expected %s, got %s", tt.expected, result)
            }
        })
    }
}
```

### Step 5: Document

```markdown
1. Update CHANGELOG.md
   - What was broken
   - What was fixed
   - Issue number

2. Add to COMMON_PITFALLS.md (if applicable)
   - Document the mistake
   - Show the fix

3. Update TROUBLESHOOTING_FAQ.md (if relevant)
```

### Step 6: Deploy & Verify

```bash
# Follow deployment workflow
# Then verify fix in production

# Check for the specific issue
sudo docker logs liquorpro-sales-prod -f | grep "SymptomOfBug"

# Should no longer appear!
```

---

## 4. Code Review Workflow

### As Reviewer

**Step 1: Prepare (5 minutes)**
```
1. Read PR description
2. Understand context and goals
3. Check related issues/PRs
4. Open CODE_REVIEW_CHECKLIST.md
```

**Step 2: Review Code (20-40 minutes)**
```
□ Understand the changes
  └─> Read diff carefully
  └─> Understand intent

□ Check implementation
  └─> Is logic correct?
  └─> Are edge cases handled?
  └─> Any potential bugs?

□ Verify tests
  └─> Adequate coverage?
  └─> Test edge cases?
  └─> Tests actually test the feature?

□ Review for patterns
  └─> Follows BEST_PRACTICES.md?
  └─> Avoids COMMON_PITFALLS.md?
  └─> Consistent with codebase?

□ Check performance
  └─> Any performance concerns?
  └─> Regex compiled properly?
  └─> Cache used appropriately?

□ Security review
  └─> No security vulnerabilities?
  └─> Input validation present?
  └─> No secrets in code?
```

**Step 3: Leave Comments (10-20 minutes)**
```
For each issue:
  1. Use appropriate template
     (from TEMPLATES_PACKAGE.md)

  2. Be specific
     - Quote the code
     - Explain the issue
     - Suggest solution

  3. Be constructive
     - Focus on code, not person
     - Explain reasoning
     - Offer to help
```

**Step 4: Make Decision**
```
Approve when:
  ✅ Code is correct
  ✅ Tests are adequate
  ✅ Follows standards
  ✅ Documentation updated
  ✅ Ready for production

Request Changes when:
  ❌ Critical issues present
  ❌ Tests insufficient
  ❌ Doesn't follow standards
  ❌ Security concerns

Comment when:
  💬 Minor suggestions
  💬 Questions for author
  💬 Nice-to-have improvements
```

### As PR Author

**Step 1: Self-Review First**
```bash
# Before requesting review
cat CODE_REVIEW_CHECKLIST.md

# Check each item
# Fix any issues found
```

**Step 2: Create Good PR**
```
Use PR template from TEMPLATES_PACKAGE.md

Include:
  ✅ Clear description
  ✅ Test results
  ✅ Screenshots (if UI changes)
  ✅ Deployment plan
  ✅ Monitoring plan
```

**Step 3: Respond to Reviews**
```
For each comment:
  1. Read carefully
  2. Understand the concern
  3. Ask questions if unclear

  Then:
  - Make requested change, OR
  - Explain why current approach is better

  Always respond to show you read it!
```

**Step 4: Make Changes**
```bash
# Make requested changes
git add .
git commit -m "review: Address review comments"

# Push
git push origin your-branch

# Re-request review
# (Click button on GitHub)
```

---

## 5. Deployment Workflow

### Pre-Deployment (15 minutes)

```bash
# 1. Verify all tests pass
./scripts/ocr_test_runner.sh

# 2. Run verification
./scripts/verify_deployment.sh

# 3. Check current production status
sudo docker ps | grep sales
sudo docker logs liquorpro-sales-prod --tail 50

# 4. Backup current version
sudo docker tag liquorpro/sales:latest liquorpro/sales:backup-$(date +%Y%m%d-%H%M)

# 5. Notify team
echo "Deploying [feature/fix] at $(date)" | send-to-slack
```

### Deployment (5 minutes)

```bash
# Use deployment checklist from TEMPLATES_PACKAGE.md

# 1. Build
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; \
  docker compose -f docker-compose.production.yml build sales"

# 2. Deploy
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; \
  docker compose -f docker-compose.production.yml up -d --no-deps sales"

# 3. Verify container started
sudo docker ps | grep sales
```

### Post-Deployment (30-60 minutes)

```bash
# 1. Immediate verification (2 min)
./scripts/verify_deployment.sh

# 2. Check for errors (5 min)
sudo docker logs liquorpro-sales-prod --tail 100 | grep -i error

# 3. Monitor metrics (30 min minimum!)
./scripts/ocr_metrics_monitor.sh 30

# 4. Extended monitoring
# Watch these metrics:
# - Accuracy (should be >95%)
# - Error rate (should be <5%)
# - Cache hit rate (should be >70%)
# - API calls (should be reduced)

# 5. If issues detected
# → Follow rollback plan
# → Investigate
# → Fix or revert
```

### Rollback (if needed)

```bash
# 1. Restore backup
sudo docker tag liquorpro/sales:backup-YYYYMMDD-HHMM liquorpro/sales:latest

# 2. Restart
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; \
  docker compose -f docker-compose.production.yml up -d --force-recreate sales"

# 3. Verify
./scripts/verify_deployment.sh

# 4. Notify team
echo "Rolled back deployment due to [reason]" | send-to-slack

# 5. Create incident report
# (Use template from TEMPLATES_PACKAGE.md)
```

---

## 6. Incident Response Workflow

### Phase 1: Detection & Triage (5-10 minutes)

```
Alert received or issue reported
  ↓
1. Acknowledge incident
   └─> Confirm you're investigating

2. Assess severity
   └─> P0: Critical (system down)
   └─> P1: High (major functionality broken)
   └─> P2: Medium (degraded service)
   └─> P3: Low (minor issue)

3. Gather initial information
   └─> What's broken?
   └─> Since when?
   └─> How many users affected?

4. Notify stakeholders
   └─> Team lead
   └─> On-call engineer
   └─> (P0/P1) Management
```

### Phase 2: Investigation (10-30 minutes)

```bash
# 1. Check system status
sudo docker ps
./scripts/verify_deployment.sh

# 2. Check recent changes
git log --since="2 hours ago" --oneline

# 3. Review logs
sudo docker logs liquorpro-sales-prod --since 30m | grep -i error
sudo docker logs liquorpro-sales-prod --tail 200

# 4. Check metrics
./scripts/ocr_metrics_monitor.sh 5

# 5. Form hypothesis
# What do you think is wrong?
```

### Phase 3: Mitigation (varies)

```
Quick Fix (if possible):
  └─> Apply immediate workaround
  └─> Verify fix works
  └─> Monitor

Rollback (if recent deployment):
  └─> Follow rollback procedure
  └─> Verify system restored
  └─> Monitor

Escalate (if can't resolve):
  └─> Call senior engineer
  └─> Provide all gathered info
  └─> Continue assisting
```

### Phase 4: Resolution & Verification (15-30 minutes)

```bash
# 1. Apply permanent fix
# (If different from mitigation)

# 2. Verify fix
./scripts/verify_deployment.sh
./scripts/ocr_metrics_monitor.sh 15

# 3. Monitor extended period
# Watch for at least 30 minutes

# 4. Confirm metrics normal
# - Accuracy back to normal?
# - Error rate acceptable?
# - No new issues?
```

### Phase 5: Post-Incident (1-2 hours)

```
1. Write incident report
   └─> Use template from TEMPLATES_PACKAGE.md
   └─> Document timeline
   └─> Explain root cause
   └─> List action items

2. Notify resolution
   └─> Update stakeholders
   └─> Confirm system stable

3. Schedule post-mortem
   └─> Within 48 hours
   └─> All involved parties
   └─> Use template from TEMPLATES_PACKAGE.md

4. Create follow-up tasks
   └─> Prevent recurrence
   └─> Improve detection
   └─> Update documentation
```

---

## 7. Onboarding Workflow

### Week 1: Foundations

**Day 1: Environment Setup (Full day)**
```
Morning:
  ☐ Get laptop/accounts set up
  ☐ Access to repositories
  ☐ Access to production (read-only)
  ☐ Clone repository
  ☐ Install dependencies

Afternoon:
  ☐ Run verification script
  ☐ Read README_OCR_IMPROVEMENTS.md
  ☐ Read OCR_QUICK_REFERENCE.md
  ☐ Skim INDEX.md to see all docs
```

**Day 2: Learn the Code (Full day)**
```
Morning:
  ☐ Read OCR_DEVELOPMENT_GUIDE.md
  ☐ Run first test
  ☐ Browse codebase

Afternoon:
  ☐ Read REAL_WORLD_EXAMPLES.md
  ☐ Study one example in detail
  ☐ Ask questions about unclear parts
```

**Day 3-5: First Contribution**
```
Task: Add one fuzzy pattern (guided)

Day 3:
  ☐ Pick a simple pattern to add
  ☐ Write tests (with mentor)
  ☐ Run tests

Day 4:
  ☐ Implement pattern
  ☐ Make tests pass
  ☐ Self-review

Day 5:
  ☐ Create PR (use template)
  ☐ Code review process
  ☐ Address comments
```

### Week 2: Building Skills

**Tasks**:
```
☐ Read BEST_PRACTICES.md
☐ Read COMMON_PITFALLS.md
☐ Add more complex feature (with guidance)
☐ Write comprehensive tests
☐ Review someone's PR (observation)
```

### Week 3: Independence

**Tasks**:
```
☐ Take a real bug from backlog
☐ Investigate independently
☐ Fix and test
☐ Document the fix
☐ Deploy to staging
```

### Week 4: Full Contributor

**Tasks**:
```
☐ Own a feature end-to-end
☐ Review others' code
☐ Deploy to production (supervised)
☐ Monitor deployment
☐ On-call shadow
```

---

## 📊 Workflow Metrics

Track these to improve workflows:

```
Cycle Time:
  - Feature: Concept → Production (target: <2 weeks)
  - Bug Fix: Report → Resolution (target: <3 days)
  - Code Review: PR Created → Approved (target: <48 hours)

Quality Metrics:
  - Test Coverage: >80%
  - Bugs Per Deploy: <2
  - Rollback Rate: <5%

Efficiency Metrics:
  - Time to First Review: <24 hours
  - PR Merge Rate: >90%
  - Deployment Frequency: 2-3 per week
```

---

## 🔄 Continuous Improvement

**Monthly Review**:
```
1. Review workflow metrics
2. Identify bottlenecks
3. Gather team feedback
4. Update workflows
5. Train team on changes
```

**Workflow Updates**:
```
When to update:
  - Process is too slow
  - Team keeps missing steps
  - New tool/practice adopted
  - Incident revealed gap

How to update:
  1. Propose change
  2. Discuss with team
  3. Update docs
  4. Communicate change
  5. Monitor adoption
```

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0

---

> **Remember**: Workflows are guides, not rules. Adapt as needed, but always maintain quality standards!
