/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // เราใช้ pages router + API routes
  experimental: {
    // ปิดสิ่งที่เกี่ยวกับ RSC/Server Actions เพื่อความเรียบง่าย
  },
};

module.exports = nextConfig;
