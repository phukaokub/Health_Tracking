-- The adopted staging project contained this untracked security-definer
-- function. It is not part of the application contract and must not be
-- callable through the public Data API.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end;
$$;

-- This trigger helper must retain definer privileges to create a profile after
-- Auth inserts a user, but it has no valid RPC caller.
revoke execute on function public.create_profile_for_new_user() from public, anon, authenticated;
