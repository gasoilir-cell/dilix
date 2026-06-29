/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  // پراکسیِ توسعه به سرویسِ Core تا CORS در dev دردسر نشود.
  async rewrites() {
    const core = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8000";
    return [{ source: "/api/:path*", destination: `${core}/:path*` }];
  },
};

export default nextConfig;
