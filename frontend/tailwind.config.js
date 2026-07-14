/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./app/**/*.{js,jsx}",
    "./components/**/*.{js,jsx}",
    "./lib/**/*.{js,jsx}",
  ],
  theme: {
    extend: {
      colors: {
        // Deep royal navy — taken from the "Namm Kural" cover.
        // Major surface stays white; navy is the SECONDARY accent for the
        // citizen app and admin. WCAG-AA on white.
        brand: {
          50:  "#eef2f7",
          100: "#d0dbe6",
          200: "#8fa5be",
          DEFAULT: "#1a3556",
          600: "#1a3556",
          700: "#132844",
          dark: "#0d1d34",
        },
        // Warm gold accent — same tone as the cover's emblem/typography.
        // Used as tertiary highlight everywhere (also drives coordinator's
        // black+gold FAB / civic card gradients).
        gold: {
          100: "#f2e4bc",
          200: "#ddc689",
          300: "#c8a04a",
          400: "#a88535",
          500: "#8c6c25",
        },
        // Beige kept for a few soft-neutral surfaces (very close to gold-100).
        beige: {
          100: "#f5efe4",
          200: "#e8dcc4",
          300: "#d6c39c",
        },
      },
      boxShadow: {
        phone: "0 25px 50px -12px rgba(0,0,0,0.45)",
      },
    },
  },
  plugins: [],
};
