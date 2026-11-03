# Supabase Auth setup for ITNSA LAB

## What changed
- `index.html` now signs in with Supabase Auth using email and password.
- User roles are read from `public.profiles`.
- Account administration calls the `admin-users` Edge Function; the service-role key is never placed in browser code.
- The existing simulator, learning modules, and local progress storage are retained.

## Deploy the Edge Function
Run these commands from the repository root with the Supabase CLI installed:

```bash
supabase login
supabase link --project-ref unzcuuebzllijochqmxo
supabase functions deploy admin-users
```

The Edge Function uses the Supabase-provided `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` environment variables. Do not put the service-role key in `index.html`, GitHub, or any browser-accessible file.

## Supabase dashboard checks
1. Authentication > Users: confirm `nurfahrifahri239@gmail.com` exists and is confirmed.
2. Table Editor > `profiles`: confirm the same email has role `superadmin`.
3. Authentication > URL Configuration: add the deployed ITNSA LAB URL to the allowed redirect URLs if email flows are enabled.

## First login
Open ITNSA LAB and sign in with `nurfahrifahri239@gmail.com` and the password set for that Supabase Auth user.

## Important
- New accounts created in the Admin panel are Supabase Auth users.
- Admins may manage ordinary users; only Superadmins may assign roles or disable accounts.
- Local progress, simulator topology, and some learning-community content remain in browser storage for now; they are not yet synchronized across devices.
- Existing local-only usernames/passwords from the old version do not become Supabase accounts automatically. Create new accounts through Supabase Auth or the Superadmin panel.

## Manual SQL already applied
The `profiles` table and its signup trigger/policies were created separately in Supabase SQL Editor. The Edge Function must be deployed before account management actions will work.