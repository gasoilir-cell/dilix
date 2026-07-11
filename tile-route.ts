import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

const SUBDOMAINS = ["mt0", "mt1", "mt2", "mt3"];

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ z: string; x: string; y: string }> }
) {
  const { z, x, y } = await params;

  if (!/^\d{1,2}$/.test(z) || !/^\d{1,7}$/.test(x) || !/^\d{1,7}$/.test(y)) {
    return new NextResponse("Bad tile coordinate", { status: 400 });
  }
  const level = Number(z);
  if (level < 0 || level > 19) {
    return new NextResponse("Tile level out of range", { status: 400 });
  }

  const sub = SUBDOMAINS[(Number(x) + Number(y)) % SUBDOMAINS.length];
  // lyrs=y → hybrid: satellite imagery + city/road/province labels
  const upstream = `https://${sub}.google.com/vt/lyrs=y&x=${x}&y=${y}&z=${z}`;

  try {
    const res = await fetch(upstream, {
      headers: {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        Referer: "https://www.google.com/maps/",
      },
      cache: "force-cache",
    });
    if (!res.ok) return new NextResponse("Upstream error", { status: 502 });
    const body = await res.arrayBuffer();
    return new NextResponse(body, {
      status: 200,
      headers: {
        "Content-Type": res.headers.get("content-type") ?? "image/jpeg",
        "Cache-Control": "public, max-age=2592000, immutable",
      },
    });
  } catch {
    return new NextResponse("Tile fetch failed", { status: 502 });
  }
}
