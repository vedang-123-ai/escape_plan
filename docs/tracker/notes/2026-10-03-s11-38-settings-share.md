# S11.38 Settings Share

- Refactored `SettingsScreen` to reuse `ShareWithFireDepartmentCard` using `activeHomeID` instead of generating its own snapshot.
- Passed `homeName` to `ConsentSheet` so it correctly names the home.
- Ensured failures are no longer silent by letting `ShareWithFireDepartmentCard` handle and display errors natively.
