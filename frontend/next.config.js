/** @type {import('next').NextConfig} */

// The /fms proxy must reach the FastAPI backend. In local dev that's
// localhost:8000; in production the frontend + backend are separate Railway
// services, so it targets the backend's public URL. Override with BACKEND_URL.
const BACKEND_URL =
  process.env.BACKEND_URL ||
  (process.env.NODE_ENV === "production"
    ? "https://nmkrl-v1-production-587d.up.railway.app"
    : "http://localhost:8000");

const nextConfig = {
  reactStrictMode: true,
  images: { unoptimized: true },

  // Proxy /fms/* → FastAPI. We avoid the /api/ prefix because Next.js
  // reserves it for its own route handlers and blocks rewrites on that path.
  async rewrites() {
    return [
      {
        source: "/fms/:path*",
        destination: `${BACKEND_URL}/:path*`,
      },
    ];
  },
};

module.exports = nextConfig;
