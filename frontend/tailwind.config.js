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
        // Calm, trustworthy slate-teal primary (cool, low-fatigue, WCAG-AA).
        brand: {
          50:  "#eef3f5",
          100: "#d9e4e8",
          200: "#b4c9d1",
          DEFAULT: "#3f6a7d",
          600: "#3f6a7d",
          700: "#345766",
          dark: "#26414d",
        },
      },
      boxShadow: {
        phone: "0 25px 50px -12px rgba(0,0,0,0.45)",
      },
    },
  },
  plugins: [],
};
