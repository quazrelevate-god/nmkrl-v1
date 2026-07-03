/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  images: { unoptimized: true },

  // Proxy /fms/* → FastAPI. We avoid the /api/ prefix because Next.js
  // reserves it for its own route handlers and blocks rewrites on that path.
  async rewrites() {
    return [
      {
        source: "/fms/:path*",
        destination: "http://localhost:8000/:path*",
      },
    ];
  },
};

module.exports = nextConfig;
