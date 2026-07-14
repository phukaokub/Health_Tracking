import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const next = url.searchParams.get("next") ?? "/account";
  return NextResponse.redirect(new URL(next, url.origin));
}
