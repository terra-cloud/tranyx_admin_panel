# Agent Memory (Tranyx Admin Portal)

## Git Commit & Push Policy
- **Rule**: When working on features or tasks, ALWAYS commit each feature or sub-task separately with clear, descriptive commit messages.
- **Rule**: NEVER run `git push` or push commits to the remote repository. The USER will decide when to push and squash commits. All commits must remain local.

## Image Upload Policy
- **Rule**: All image uploading must be performed using the `ImgBBService` (or `imageBBService`).
- **Reasoning**: Directly uploading/storing large Base64 Data URLs inside Firestore documents exceeds Firestore's 1MB document size limit, causing database errors. Always upload images to ImgBB and store the returned HTTP URLs in Firestore.

## Firestore Security Rules Cross-Project Synchronization
- **Shared Architecture**: `tranyx_admin_portal` interacts with `tranyx-dev`, `tranyx-uat`, and `tranyx-app`.
- **Single Source of Truth**: All security rules are centrally maintained in `tranyx_workspace/firestore_rules/`.
- **DO NOT Edit `firestore.rules` Directly**: Local `firestore.rules` is auto-synchronized from `tranyx_workspace`.
- **Deployment**: Use `dart run tool/sync_rules.dart` or `dart run tool/deploy_rules.dart [dev|uat|prod|all]`. The `firebase.json` predeploy hook automatically keeps rules synchronized.
