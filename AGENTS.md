# Antigravity Admin Portal Guidelines & Operational Memory

## Git Commit & Push Workflow
- **Commit Each Feature Separately**: When working on features, tasks, or bug fixes, always stage and commit each distinct unit of work separately with clear, conventional commit messages (`feat: ...`, `fix: ...`, `refactor: ...`, `test: ...`). This provides a clear, granular ledger of completed work.
- **NEVER Push to Remote**: NEVER execute `git push`. The user maintains full control and will decide when to push and squash commits to remote. All commits made by the agent must remain strictly local.

## Image Upload Policy
- **Rule**: All image uploading must be performed using the `ImgBBService` (or `imageBBService`).
- **Reasoning**: Directly uploading/storing large Base64 Data URLs inside Firestore documents exceeds Firestore's 1MB document size limit, causing database errors. Always upload images to ImgBB and store the returned HTTP URLs in Firestore.

## Shared Firestore Database Architecture & Security Rules Synchronization
- **Shared Architecture**: `tranyx_admin_portal` operates against the shared Firebase database environments (`tranyx-dev`, `tranyx-uat`, `tranyx-app`) alongside `tranyx_workspace` (Web & Mobile).
- **Single Source of Truth**: The single authoritative source of truth for all Cloud Firestore security rules is located in `tranyx_workspace/firestore_rules/`.
- **DO NOT Edit `firestore.rules` Directly in this Project**:
  - `firestore.rules` in this repository is auto-generated and mirrored from `tranyx_workspace`.
  - Manual, standalone modifications here will be overwritten upon build/deploy and must NOT be made.
  - To request or make rule changes, modify the modular files in `/Users/zeuscajurao/Desktop/tranyx_workspace/firestore_rules/` and recompile.
- **Predeploy Safety Hook**:
  - `firebase.json` contains a `predeploy` hook executing `dart run tool/sync_rules.dart`. Whenever `firebase deploy` is executed from this folder, it automatically pulls the latest unified rules from `tranyx_workspace` before uploading to Firebase.
- **Safe Rules Deployment**:
  - To deploy rules to any target environment from this project, run:
    ```bash
    dart run tool/deploy_rules.dart [dev|uat|prod|all]
    ```
  - This automatically validates, synchronizes, and deploys the unified ruleset safely.
