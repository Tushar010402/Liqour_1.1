# OCR Development - Templates Package

**Purpose**: Ready-to-use templates for common tasks
**Usage**: Copy, fill in, and use
**Last Updated**: January 15, 2025

---

## 📑 Table of Contents

1. [Pull Request Template](#pull-request-template)
2. [Bug Report Template](#bug-report-template)
3. [Feature Request Template](#feature-request-template)
4. [Incident Report Template](#incident-report-template)
5. [Code Review Comment Templates](#code-review-comment-templates)
6. [Test Case Template](#test-case-template)
7. [Deployment Checklist Template](#deployment-checklist-template)
8. [Post-Mortem Template](#post-mortem-template)
9. [Knowledge Transfer Template](#knowledge-transfer-template)

---

## 1. Pull Request Template

```markdown
# [Brief Description of Changes]

## 🎯 What

[Describe what this PR does in 2-3 sentences]

## 🤔 Why

[Explain why this change is needed]

Related Issue: #[issue-number] (if applicable)

## 🔨 How

[High-level description of approach]

### Key Changes:
- [ ] Change 1: [file:line] - [description]
- [ ] Change 2: [file:line] - [description]
- [ ] Change 3: [file:line] - [description]

## 🧪 Testing

### Test Coverage:
- [ ] Unit tests added/updated
- [ ] Coverage: [X]% (new code)
- [ ] All tests passing
- [ ] Race detection passed (`go test -race`)

### Test Results:
```
[Paste test output]
```

### Manual Testing:
- [ ] Tested locally
- [ ] Tested in staging (if applicable)
- [ ] Monitored for [X] minutes

## 📊 Performance Impact

- [ ] No performance impact
- [ ] Performance improved: [describe]
- [ ] Performance measured: [before/after metrics]

## 🚀 Deployment

### Deployment Plan:
- [ ] Standard deployment
- [ ] Requires database migration
- [ ] Requires configuration change
- [ ] Incremental rollout recommended

### Monitoring Plan:
- [ ] Monitor for [X] minutes post-deployment
- [ ] Watch metrics: [list specific metrics]
- [ ] Alert thresholds: [list any special alerts]

### Rollback Plan:
- [ ] Standard rollback (revert commit)
- [ ] Custom rollback steps: [describe if needed]

## 📝 Documentation

- [ ] Code comments added/updated
- [ ] README updated (if needed)
- [ ] CHANGELOG updated
- [ ] Best practices updated (if applicable)

## ✅ Pre-Merge Checklist

- [ ] Self-reviewed using CODE_REVIEW_CHECKLIST.md
- [ ] No common pitfalls (checked COMMON_PITFALLS.md)
- [ ] Follows BEST_PRACTICES.md standards
- [ ] All CI checks passing
- [ ] No merge conflicts
- [ ] Approved by at least one reviewer

## 📸 Screenshots (if applicable)

[Add screenshots for UI changes]

## 🔗 Related Links

- Related PR: #[pr-number]
- Documentation: [link]
- Issue tracker: [link]

## 💬 Additional Notes

[Any additional context, concerns, or questions for reviewers]

---

**Reviewer Notes:**
- Priority: [High/Medium/Low]
- Estimated Review Time: [X minutes]
- Focus Areas: [List specific areas needing careful review]
```

---

## 2. Bug Report Template

```markdown
# 🐛 Bug Report: [Brief Description]

## 📋 Bug Summary

**Severity**: [Critical/High/Medium/Low]
**Frequency**: [Always/Often/Sometimes/Rare]
**Affected Users**: [Percentage or number]

## 🔍 Description

[Detailed description of the bug]

## 📍 Location

**File(s)**: [List affected files]
**Function(s)**: [List affected functions]
**Lines**: [Approximate line numbers if known]

## 🔄 Steps to Reproduce

1. [Step 1]
2. [Step 2]
3. [Step 3]
4. [Observe bug]

## ✅ Expected Behavior

[What should happen]

## ❌ Actual Behavior

[What actually happens]

## 📊 Impact

**Accuracy Impact**: [+/-X%]
**Performance Impact**: [Slower/Faster by X]
**User Impact**: [How users are affected]

## 📸 Evidence

### Logs:
```
[Paste relevant log entries]
```

### Screenshots:
[If applicable]

### Test Case:
```go
// Test case that reproduces the bug
func TestBugReproduction(t *testing.T) {
    // Test code here
}
```

## 🔬 Investigation

### Hypothesis:
[What you think is causing the bug]

### Evidence:
- [Finding 1]
- [Finding 2]
- [Finding 3]

## 💡 Proposed Solution

[Your proposed fix]

### Alternative Solutions:
1. [Alternative 1]
2. [Alternative 2]

## ⚠️  Workaround

[Temporary workaround if available]

## 📅 Timeline

**Discovered**: [Date]
**Reported**: [Date]
**Target Fix**: [Date]

## 🔗 Related

- Related Bug: #[bug-number]
- Related PR: #[pr-number]
- Documentation: [link]
```

---

## 3. Feature Request Template

```markdown
# ✨ Feature Request: [Feature Name]

## 🎯 Feature Summary

**Priority**: [High/Medium/Low]
**Effort**: [Small/Medium/Large]
**Type**: [Enhancement/New Feature]

## 🤔 Problem Statement

[What problem does this solve?]

### Current Situation:
[Describe current state and limitations]

### Desired Outcome:
[What should be possible after this feature?]

## 👥 User Story

As a [type of user]
I want to [action]
So that [benefit]

## 📋 Requirements

### Functional Requirements:
- [ ] Requirement 1
- [ ] Requirement 2
- [ ] Requirement 3

### Non-Functional Requirements:
- [ ] Performance: [target metrics]
- [ ] Accuracy: [target metrics]
- [ ] Scalability: [requirements]

## 💡 Proposed Solution

### High-Level Approach:
[Describe the approach]

### Technical Design:
1. [Component 1]: [Description]
2. [Component 2]: [Description]
3. [Component 3]: [Description]

### Example Code:
```go
// Example of how this would work
func NewFeature() {
    // Implementation sketch
}
```

## 📊 Success Metrics

**How we'll measure success:**
- Metric 1: [target value]
- Metric 2: [target value]
- Metric 3: [target value]

## 🚧 Implementation Plan

### Phase 1: Foundation
- [ ] Task 1
- [ ] Task 2

### Phase 2: Core Feature
- [ ] Task 3
- [ ] Task 4

### Phase 3: Polish & Testing
- [ ] Task 5
- [ ] Task 6

## ⚠️  Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| [Risk 1] | [High/Med/Low] | [High/Med/Low] | [How to mitigate] |
| [Risk 2] | [High/Med/Low] | [High/Med/Low] | [How to mitigate] |

## 🔀 Alternatives Considered

### Alternative 1: [Name]
- Pros: [List]
- Cons: [List]
- Why not chosen: [Reason]

### Alternative 2: [Name]
- Pros: [List]
- Cons: [List]
- Why not chosen: [Reason]

## 📚 References

- Similar feature in: [link]
- Research: [link]
- Documentation: [link]

## 💬 Discussion

[Open questions, concerns, or discussion points]
```

---

## 4. Incident Report Template

```markdown
# 🚨 Incident Report: [Brief Title]

**Incident ID**: INC-[YYYY-MM-DD]-[###]
**Severity**: [P0 - Critical / P1 - High / P2 - Medium / P3 - Low]
**Status**: [Open / Investigating / Resolved / Closed]

## 📅 Timeline

| Time | Event |
|------|-------|
| [HH:MM] | Incident detected |
| [HH:MM] | Team notified |
| [HH:MM] | Investigation started |
| [HH:MM] | Root cause identified |
| [HH:MM] | Fix implemented |
| [HH:MM] | Incident resolved |
| [HH:MM] | Monitoring period ended |

**Total Duration**: [X hours Y minutes]
**Time to Detection**: [X minutes]
**Time to Resolution**: [Y minutes]

## 📋 Summary

[1-2 sentence summary of what happened]

## 🔍 Impact

**Users Affected**: [Number or percentage]
**Accuracy Impact**: [+/- X%]
**Services Affected**: [List]
**Duration**: [Start time - End time]

### Business Impact:
- [Impact 1]
- [Impact 2]
- [Impact 3]

## 🔬 Root Cause

### What Happened:
[Detailed explanation]

### Why It Happened:
[Root cause analysis]

### Contributing Factors:
1. [Factor 1]
2. [Factor 2]
3. [Factor 3]

## 🔍 Detection

**How Detected**: [Monitoring alert / User report / Other]
**Detection Method**: [Specific alert or report]
**Could Have Detected Earlier**: [Yes/No - explain]

## 🛠️  Resolution

### Immediate Fix:
```
[Steps taken to resolve immediately]
```

### Permanent Fix:
```
[Steps for permanent resolution]
```

### Verification:
- [ ] Fix verified in production
- [ ] Metrics returned to normal
- [ ] No regression detected
- [ ] Monitoring confirmed stable

## 📊 Metrics

### Before Incident:
- Accuracy: [X%]
- Error Rate: [Y%]
- Response Time: [Z ms]

### During Incident:
- Accuracy: [X%]
- Error Rate: [Y%]
- Response Time: [Z ms]

### After Resolution:
- Accuracy: [X%]
- Error Rate: [Y%]
- Response Time: [Z ms]

## ✅ Action Items

### Immediate (This Week):
- [ ] [Action 1] - Owner: [Name] - Due: [Date]
- [ ] [Action 2] - Owner: [Name] - Due: [Date]

### Short-term (This Month):
- [ ] [Action 3] - Owner: [Name] - Due: [Date]
- [ ] [Action 4] - Owner: [Name] - Due: [Date]

### Long-term (This Quarter):
- [ ] [Action 5] - Owner: [Name] - Due: [Date]
- [ ] [Action 6] - Owner: [Name] - Due: [Date]

## 🎓 Lessons Learned

### What Went Well:
1. [Success 1]
2. [Success 2]

### What Could Be Improved:
1. [Improvement 1]
2. [Improvement 2]

### Prevention Measures:
1. [Measure 1]
2. [Measure 2]

## 📝 Communication

### Notifications Sent:
- [HH:MM] - [Who notified] - [Channel]
- [HH:MM] - [Who notified] - [Channel]

### Updates Provided:
- [HH:MM] - [Update summary]
- [HH:MM] - [Update summary]

## 🔗 Related

- Similar Incident: [INC-ID]
- Related PR: #[pr-number]
- Post-Mortem Doc: [link]

## 👥 Response Team

- Incident Commander: [Name]
- Technical Lead: [Name]
- Communications: [Name]
- Support: [Names]

---

**Report Prepared By**: [Name]
**Date**: [Date]
**Reviewed By**: [Name(s)]
```

---

## 5. Code Review Comment Templates

### Requesting Critical Fix
```markdown
🔴 **Critical Issue**

**Problem**: [Describe the issue]

**Location**: [file.go:line]

**Impact**: [What will happen if not fixed]

**Required Fix**:
```go
// Current (incorrect)
[current code]

// Should be
[corrected code]
```

**Why**: [Explanation]

**Must fix before merge** ✋
```

### Suggesting Improvement
```markdown
💡 **Suggestion**

**Current approach works**, but we could improve:

[Your suggestion]

**Benefits**:
- [Benefit 1]
- [Benefit 2]

**Optional**: Can be done in follow-up PR if preferred.
```

### Asking for Clarification
```markdown
❓ **Question**

I'm not sure I understand [specific part].

Could you explain:
1. [Question 1]
2. [Question 2]

This will help me review more effectively.
```

### Pointing Out Best Practice
```markdown
📘 **Best Practice**

Per `BEST_PRACTICES.md` section [X.Y], we should:

[Best practice description]

**Suggested change**:
```go
[code following best practice]
```

**Reference**: BEST_PRACTICES.md:[line]
```

### Identifying Pitfall
```markdown
⚠️  **Common Pitfall**

This looks like pitfall #[X] from `COMMON_PITFALLS.md`:

**Issue**: [Description of pitfall]

**Why it's problematic**: [Explanation]

**Solution**:
```go
[corrected code]
```

**Reference**: COMMON_PITFALLS.md:[section]
```

### Approving with Minor Notes
```markdown
✅ **LGTM** (Looks Good To Me)

**Reviewed**:
- ✅ Code quality
- ✅ Tests comprehensive
- ✅ Documentation updated
- ✅ No security concerns

**Minor notes** (can be addressed in follow-up):
- [Note 1]
- [Note 2]

**Approved for merge** 👍

**Reminder**: Monitor after deployment!
```

---

## 6. Test Case Template

```go
package services

import (
    "testing"
)

// Test[FunctionName]_[Scenario]
func TestYourFunction_HappyPath(t *testing.T) {
    // Arrange
    input := "test input"
    expected := "expected output"

    // Act
    result := YourFunction(input)

    // Assert
    if result != expected {
        t.Errorf("Expected %s, got %s", expected, result)
    }
}

// Table-driven test template
func TestYourFunction_AllScenarios(t *testing.T) {
    tests := []struct {
        name        string
        input       string
        expected    string
        expectError bool
    }{
        // Happy path
        {
            name:        "Standard input",
            input:       "valid input",
            expected:    "expected output",
            expectError: false,
        },

        // Edge cases
        {
            name:        "Empty input",
            input:       "",
            expected:    "",
            expectError: true,
        },
        {
            name:        "Boundary value",
            input:       "boundary",
            expected:    "boundary result",
            expectError: false,
        },

        // Error cases
        {
            name:        "Invalid input",
            input:       "invalid",
            expected:    "",
            expectError: true,
        },

        // OCR variations (if applicable)
        {
            name:        "OCR error 0→O",
            input:       "9Oml",  // Should match 90ml
            expected:    "90ml",
            expectError: false,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // Act
            result, err := YourFunction(tt.input)

            // Assert error expectation
            if tt.expectError && err == nil {
                t.Error("Expected error but got none")
            }
            if !tt.expectError && err != nil {
                t.Errorf("Unexpected error: %v", err)
            }

            // Assert result
            if result != tt.expected {
                t.Errorf("Expected %q, got %q", tt.expected, result)
            }
        })
    }
}

// Benchmark template
func BenchmarkYourFunction(b *testing.B) {
    input := "test input"

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _ = YourFunction(input)
    }
}
```

---

## 7. Deployment Checklist Template

```markdown
# Deployment Checklist: [Feature/Fix Name]

**Date**: [YYYY-MM-DD]
**Deployer**: [Name]
**PR**: #[pr-number]
**Environment**: [Staging/Production]

## ⏰ Timing

**Planned Time**: [HH:MM]
**Off-Peak**: [Yes/No]
**User Impact**: [Low/Medium/High]

## ✅ Pre-Deployment

### Code Quality:
- [ ] All tests passing (local)
- [ ] All tests passing (CI)
- [ ] Code reviewed and approved
- [ ] No merge conflicts
- [ ] CHANGELOG updated

### Testing:
- [ ] Unit tests: [X/Y passing]
- [ ] Integration tests: [X/Y passing]
- [ ] Manual testing complete
- [ ] Race detection passed
- [ ] Coverage: [X%]

### Documentation:
- [ ] README updated (if needed)
- [ ] API docs updated (if needed)
- [ ] Configuration docs updated (if needed)
- [ ] Deployment notes prepared

### Preparation:
- [ ] Backup created
- [ ] Rollback plan documented
- [ ] Team notified
- [ ] Monitoring dashboards ready
- [ ] Alert thresholds configured

## 🚀 Deployment Steps

### Step 1: Build
```bash
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; \
  docker compose -f docker-compose.production.yml build sales"
```
- [ ] Build successful
- [ ] No errors in build output
- [ ] Image size reasonable

### Step 2: Deploy
```bash
sudo -E bash -c "set -a; source .env.production 2>/dev/null; set +a; \
  docker compose -f docker-compose.production.yml up -d --no-deps sales"
```
- [ ] Deploy successful
- [ ] Container started
- [ ] Health check passing

### Step 3: Verify
```bash
./scripts/verify_deployment.sh
```
- [ ] All checks passing
- [ ] No errors in verification
- [ ] Services responding

## 📊 Post-Deployment Monitoring

### Immediate (5 minutes):
- [ ] Container running
- [ ] No critical errors in logs
- [ ] Health endpoint responding
- [ ] Basic functionality working

### Short-term (30 minutes):
```bash
./scripts/ocr_metrics_monitor.sh 30
```
- [ ] Accuracy: [Current: X%] [Target: >95%]
- [ ] Error rate: [Current: X%] [Target: <5%]
- [ ] Cache hit rate: [Current: X%] [Target: >70%]
- [ ] Response time: [Current: X ms] [Target: <500ms]

### Extended (2 hours):
- [ ] No new errors
- [ ] Metrics stable
- [ ] No user complaints
- [ ] Performance acceptable

## 📈 Metrics Snapshot

### Before Deployment:
- Accuracy: [X%]
- Error Rate: [Y%]
- API Calls: [Z/hour]
- Response Time: [W ms]

### After Deployment:
- Accuracy: [X%]
- Error Rate: [Y%]
- API Calls: [Z/hour]
- Response Time: [W ms]

## 🔄 Rollback Plan

**If issues occur**:

1. Immediate rollback:
```bash
docker tag liquorpro/sales:backup liquorpro/sales:latest
docker-compose up -d --force-recreate sales
```

2. Verify rollback:
```bash
./scripts/verify_deployment.sh
```

3. Investigate issue

## ✅ Sign-Off

- [ ] Deployment successful
- [ ] Monitoring complete
- [ ] Metrics acceptable
- [ ] Team notified of completion
- [ ] Documentation updated

**Completed By**: [Name]
**Completed At**: [HH:MM]
**Status**: [Success/Partial/Rollback]

## 📝 Notes

[Any observations, issues, or learnings from this deployment]
```

---

## 8. Post-Mortem Template

```markdown
# Post-Mortem: [Incident Title]

**Date**: [YYYY-MM-DD]
**Facilitator**: [Name]
**Attendees**: [Names]
**Incident**: [INC-YYYY-MM-DD-###]

## 📋 Executive Summary

[2-3 sentence summary for leadership]

**Impact**: [Brief impact statement]
**Root Cause**: [One sentence]
**Status**: [Resolved / Monitoring / In Progress]

## 📊 By The Numbers

| Metric | Value |
|--------|-------|
| **Detection Time** | [X minutes] |
| **Resolution Time** | [Y minutes] |
| **Total Downtime** | [Z minutes] |
| **Users Affected** | [N users / X%] |
| **Accuracy Impact** | [+/- X%] |
| **Data Loss** | [None / Minimal / Significant] |

## 🎯 What Happened

### Incident Timeline:

**[HH:MM]** - Normal Operations
- [Brief description of normal state]

**[HH:MM]** - First Symptom
- [What was first noticed]
- [Who noticed it / How]

**[HH:MM]** - Incident Confirmed
- [How confirmed]
- [Actions taken]

**[HH:MM]** - Investigation Started
- [What was investigated]
- [Initial hypothesis]

**[HH:MM]** - Root Cause Identified
- [What was found]
- [How it was identified]

**[HH:MM]** - Fix Applied
- [What fix was applied]
- [How it was tested]

**[HH:MM]** - Resolution Verified
- [How verified]
- [Metrics checked]

**[HH:MM]** - Monitoring Period Ended
- [Final status]
- [All clear confirmed]

## 🔍 Root Cause Analysis

### The 5 Whys:

1. **Why did [incident] occur?**
   - [Answer]

2. **Why [answer to #1]?**
   - [Answer]

3. **Why [answer to #2]?**
   - [Answer]

4. **Why [answer to #3]?**
   - [Answer]

5. **Why [answer to #4]?**
   - [ROOT CAUSE]

### Contributing Factors:
1. [Factor 1]
2. [Factor 2]
3. [Factor 3]

### What Made It Worse:
- [Factor that increased severity/duration]

### What Made It Better:
- [Factor that helped resolution]

## ✅ What Went Well

1. **[Success 1]**
   - [Details]
   - [Why it worked well]

2. **[Success 2]**
   - [Details]
   - [Why it worked well]

3. **[Success 3]**
   - [Details]
   - [Why it worked well]

## ❌ What Didn't Go Well

1. **[Problem 1]**
   - [Details]
   - [Impact]
   - [How to improve]

2. **[Problem 2]**
   - [Details]
   - [Impact]
   - [How to improve]

3. **[Problem 3]**
   - [Details]
   - [Impact]
   - [How to improve]

## 🎓 Lessons Learned

### Technical Lessons:
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

### Process Lessons:
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

### Team Lessons:
1. [Lesson 1]
2. [Lesson 2]
3. [Lesson 3]

## 🛡️  Prevention

### Immediate Actions (This Week):
- [ ] [Action 1] - Owner: [Name] - Due: [Date]
- [ ] [Action 2] - Owner: [Name] - Due: [Date]

### Short-term Actions (This Month):
- [ ] [Action 3] - Owner: [Name] - Due: [Date]
- [ ] [Action 4] - Owner: [Name] - Due: [Date]

### Long-term Actions (This Quarter):
- [ ] [Action 5] - Owner: [Name] - Due: [Date]
- [ ] [Action 6] - Owner: [Name] - Due: [Date]

### Monitoring Improvements:
- [ ] [Monitoring change 1]
- [ ] [Monitoring change 2]

### Testing Improvements:
- [ ] [Test to add 1]
- [ ] [Test to add 2]

### Documentation Improvements:
- [ ] [Doc to update 1]
- [ ] [Doc to update 2]

## 📚 Updated Documentation

- [ ] TROUBLESHOOTING_FAQ.md updated
- [ ] COMMON_PITFALLS.md updated (if applicable)
- [ ] Runbooks updated
- [ ] Monitoring docs updated

## 🔗 References

- Incident Report: [INC-YYYY-MM-DD-###]
- Related PR: #[pr-number]
- Metrics Dashboard: [link]
- Logs: [link or attachment]

## 💬 Discussion Notes

[Key points from post-mortem discussion]

---

**Next Review**: [Date]
**Follow-up Owner**: [Name]
```

---

## 9. Knowledge Transfer Template

```markdown
# Knowledge Transfer: [Topic]

**From**: [Name]
**To**: [Name(s)]
**Date**: [YYYY-MM-DD]
**Session Duration**: [X hours]

## 🎯 Transfer Objectives

By the end of this transfer, recipient should be able to:
- [ ] [Objective 1]
- [ ] [Objective 2]
- [ ] [Objective 3]

## 📋 Topics Covered

### Topic 1: [Name]
**Duration**: [X minutes]

**Key Concepts**:
- [Concept 1]
- [Concept 2]

**Code Locations**:
- [file.go:line] - [description]
- [file.go:line] - [description]

**Hands-On Exercise**:
[Exercise description]

**Resources**:
- [Document/Link 1]
- [Document/Link 2]

---

### Topic 2: [Name]
**Duration**: [X minutes]

[Same format as Topic 1]

---

## 🔧 Practical Exercises

### Exercise 1: [Title]
**Objective**: [What to accomplish]

**Steps**:
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Outcome**: [What success looks like]

**Time**: [X minutes]

---

## 📚 Essential Reading

**Before Session**:
- [ ] [Document 1]
- [ ] [Document 2]

**After Session**:
- [ ] [Document 3]
- [ ] [Document 4]

## 🎓 Knowledge Verification

### Questions to Answer:
1. [Question 1]
2. [Question 2]
3. [Question 3]

### Tasks to Complete:
- [ ] [Task 1]
- [ ] [Task 2]
- [ ] [Task 3]

## 🆘 Support Resources

**People to Contact**:
- [Name 1] - [Expertise] - [Contact]
- [Name 2] - [Expertise] - [Contact]

**Documentation**:
- [Doc 1] - [When to use]
- [Doc 2] - [When to use]

**Tools**:
- [Tool 1] - [Purpose] - [How to access]
- [Tool 2] - [Purpose] - [How to access]

## ✅ Transfer Completion

### Recipient Sign-Off:
- [ ] Understand core concepts
- [ ] Can complete basic tasks independently
- [ ] Know where to find resources
- [ ] Know who to contact for help

**Recipient Signature**: _________________ Date: _______

### Transferer Sign-Off:
- [ ] All topics covered
- [ ] Exercises completed
- [ ] Questions answered
- [ ] Recipient is ready

**Transferer Signature**: _________________ Date: _______

## 📝 Notes & Follow-Up

**Open Questions**:
1. [Question]
2. [Question]

**Follow-Up Actions**:
- [ ] [Action 1] - Owner: [Name] - Due: [Date]
- [ ] [Action 2] - Owner: [Name] - Due: [Date]

**Next Session** (if needed): [Date/Time]
```

---

## 📖 How to Use These Templates

1. **Find the right template** for your task
2. **Copy the template** to a new file
3. **Fill in all [bracketed] sections**
4. **Delete sections** that don't apply
5. **Add custom sections** as needed
6. **Review before submitting**

## 🔄 Keeping Templates Updated

- Update templates based on team feedback
- Add new templates as needs arise
- Version templates (add date to filename)
- Share template improvements with team

---

**Last Updated**: January 15, 2025
**Version**: 1.0.0
**Maintained By**: Engineering Team

---

> **Tip**: Bookmark this file for quick access to all templates!
