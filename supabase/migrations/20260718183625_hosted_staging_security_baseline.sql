-- The adopted staging project contained this untracked security-definer
-- function. It is not part of the application contract and must not be
-- callable through the public Data API.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- This trigger helper must retain definer privileges to create a profile after
-- Auth inserts a user, but it has no valid RPC caller.
revoke execute on function public.create_profile_for_new_user() from public, anon, authenticated;
