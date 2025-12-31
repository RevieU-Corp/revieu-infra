# Git Workflow Standard

Guidelines for branch management, code submission, and repository synchronization.

## Phase 1: Branch Management

Before starting work, ensure your local repository is up to date and you are on the correct branch.

### 1. Check Current Status
```bash
git branch -a
git status
```

### 2. Branching Strategy
Naming convention: `<type>/<issue-id>-<description>`

| Branch Prefix | Source Branch | Target Branch | Description |
| :--- | :--- | :--- | :--- |
| **`feat/`** | `dev` | `dev` | **Functionality**: New features or enhancements. |
| **`fix/`** | `dev` | `dev` | **Bug Fix**: Resolving issues found in testing/staging. |
| **`refactor/`** | `dev` | `dev` | **Refactoring**: Code optimization without changing behavior. |
| **`hotfix/`** | `main` | `main` & `dev` | **Emergency**: Critical fixes for Production failures. |

### 3. Create or Switch Branch
```bash
# If not on feature branch, create new one:
git checkout -b <type>/<issue-id>-<description>

# If branch exists:
git checkout <branch-name>
```

---

## Phase 2: Inspection & Staging

### 4. Review Changes
Always inspect your code before staging.
```bash
git diff         # Detailed code changes
git diff --stat  # Summary of changed files
```

### 5. Stage Changes
```bash
git add .        # Stage all changes (most common)
git add <file>   # Stage specific file
```

---

## Phase 3: Committing

### 6. Commit Message Format
Use the Conventional Commits specification:
```text
<type>(<scope>): <subject>

<body> (optional)
```

| Type | Description |
| :--- | :--- |
| **feat** | A new feature |
| **fix** | A bug fix |
| **docs** | Documentation only changes |
| **style** | Formatting, missing semi-colons, etc (no logic change) |
| **refactor** | Code change that neither fixes a bug nor adds a feature |
| **perf** | Code change that improves performance |
| **test** | Adding missing tests or correcting existing tests |
| **chore** | Changes to the build process or auxiliary tools/libraries |

**Scopes (Examples):**
- **Frontend**: `auth`, `ui`, `router`, `api-client`
- **Backend**: `user-svc`, `db`, `gateway`, `auth-svc`

**Example Commit:**
```bash
git commit -m "feat(auth): add google oauth2 login flow"
```

---

## Phase 4: Syncing & Pushing

### 7. Push to Remote
```bash
git push origin <type>/<issue-id>-<description>
```

---
Wait for PR to be merged and user ensure to continue to next step.

## Phase 5: Post-Merge Cleanup

Perform these steps after your Pull Request has been merged on GitHub.

### 8. Update Local Repository
```bash
# Fetch updates and prune deleted remote branches
git fetch --all --prune
```

### 9. Switch & Pull

if exists dev branch:
```bash
git checkout dev  # or main
git pull origin dev
```

if exists main branch:
```bash 
git checkout main
git pull origin main
```

### 10. Delete Local Feature Branch
```bash
git branch -d <type>/<issue-id>-<description>
```
