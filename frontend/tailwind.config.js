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
        // Maroon primary palette (replaces the previous blue brand).
        brand: {
          50:  "#f8ecec",
          100: "#eecfcf",
          200: "#ddaaaa",
          DEFAULT: "#7a1c1c",
          600: "#7a1c1c",
          700: "#5f1414",
          dark: "#4c0f0f",
        },
      },
      boxShadow: {
        phone: "0 25px 50px -12px rgba(0,0,0,0.45)",
      },
    },
  },
  plugins: [],
};
