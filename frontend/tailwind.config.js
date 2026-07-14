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
        // Royal algae green — deep, mossy, trustworthy (WCAG-AA compliant on white).
        brand: {
          50:  "#e8f2ec",
          100: "#c9e0d1",
          200: "#94c0a3",
          DEFAULT: "#0f5641",
          600: "#0f5641",
          700: "#0b4432",
          dark: "#083428",
        },
        // Beige used for uniform highlight borders (replaces the earlier gold).
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
