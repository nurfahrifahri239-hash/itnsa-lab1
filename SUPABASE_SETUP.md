# Supabase Auth setup for ITNSA LAB

## What changed
- `index.html` now signs in with Supabase Auth using email and password.
- User roles are read from `public.profiles`.
- Account administration calls the `admin-users` Edge Function; the service-role key is never placed in browser code.
- The existing simulator, learning modules, and local progress storage are retained.
- The Discussion tab is backed by Supabase tables with Row Level Security; other learning data remains browser-local.

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
- Learning history, scores, progress, simulator topology, notes, and Admin suggestions remain browser-local and are not synchronized across devices.
- Discussion topics, replies, likes, and reports are shared through Supabase for signed-in users.
- Existing local-only usernames/passwords from the old version do not become Supabase accounts automatically. Create new accounts through Supabase Auth or the Superadmin panel.

## Manual SQL already applied
The `profiles` table and its signup trigger/policies were created separately in Supabase SQL Editor. The Edge Function must be deployed before account management actions will work.

## Enable shared Discussion (required once)

1. Open Supabase Dashboard for project `unzcuuebzllijochqmxo`.
2. Open **SQL Editor** and create a new query.
3. Copy and run the complete contents of [`supabase/discussion.sql`](./supabase/discussion.sql).
4. Refresh ITNSA LAB and open **Diskusi**. Use **Muat ulang diskusi** if needed.

### Discussion access rules

- All signed-in users (User, Admin, Superadmin) can read visible topics and replies, create topics, reply, and like.
- Users can edit/delete their own topics and replies.
- Topic owners can mark a reply as the solution.
- Admin and Superadmin can lock/hide topics and review/close reports.
- Hidden topics are visible only to their owner and moderators.
- RLS enforces these rules in Supabase; browser-side checks are only for interface behavior.

### Storage boundaries

- **Supabase shared:** Discussion topics, replies, likes, and moderation reports.
- **Local to each browser:** learning history, quiz scores, progress, notes, simulator state, and suggestions.
- Discussion does not currently use live push updates; use **Muat ulang diskusi** to fetch the latest shared posts.

### Verification checklist

1. Sign in as User A in one browser and post a discussion topic.
2. Sign in as User B in another browser/private window; confirm the topic appears.
3. Reply and like as User B; refresh User A and confirm both changes appear.
4. Confirm User B cannot edit/delete User A's topic.
5. Confirm Admin can lock/hide a topic and review reports.
6. Confirm local scores/history remain on the browser where they were created.
