# Safe user provisioning

The user-management flow now validates the two business identifiers that can make the Auth database trigger fail:

- normalized email address
- employee number

Duplicates are rejected before creating the Auth identity, so the UI can display a precise Arabic message instead of the generic `Database error creating new user`.

If profile activation or role assignment fails after Auth creation, the server deletes the new Auth identity. This compensating action prevents half-created users.

Passwords are rendered with a password input, require at least eight characters, and use the browser's new-password autocomplete mode.

This increment changes application code only and requires no database migration.
