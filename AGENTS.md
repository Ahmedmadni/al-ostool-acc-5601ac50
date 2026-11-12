# Architecture and validation rules

- Keep authoritative settlement validation in database RPCs; browser-calculated values are previews, not trusted financial records.
- Run HR hardening regression SQL only against an independent synthetic fixture database; production checks must inspect catalog definitions and privileges without creating test settlements.