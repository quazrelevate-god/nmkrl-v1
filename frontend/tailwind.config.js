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
        brand: {
          DEFAULT: "#1d4ed8", // primary blue used across the app
          dark: "#1e3a8a",
        },
      },
      boxShadow: {
        phone: "0 25px 50px -12px rgba(0,0,0,0.45)",
      },
    },
  },
  plugins: [],
};
