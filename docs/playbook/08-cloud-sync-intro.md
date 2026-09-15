# S8 — Cloud Sync & Authentication Arc

This arc introduces multi-user accounts and cloud synchronization, replacing the previous local-only privacy constraint.

**Goal:** Allow users to create accounts, store their home models safely in the cloud, and sync them across devices.

## Sessions
- **S8.1**: Backend MongoDB Integration. Setup MongoDB, define user schemas, and connect FastAPI.
- **S8.2**: Backend Authentication. Implement JWT/OAuth, secure endpoints, and user session management.
- **S8.3**: iOS Auth UI. Add Login and Registration screens to the iOS app.
- **S8.4**: iOS Cloud Sync. Implement the upload/download and merging logic for HomeModels using the secured endpoints.
