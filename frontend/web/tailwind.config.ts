import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: "class",
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        // Primary — بنفش‌آبی زنده (مدرن + اعتماد)
        primary: {
          50:  "#EEF2FF",
          100: "#E0E7FF",
          200: "#C7D2FE",
          300: "#A5B4FC",
          400: "#818CF8",
          500: "#6366F1",
          600: "#4F46E5",
          700: "#4338CA",
          800: "#3730A3",
          900: "#1E1B4B",
          950: "#0D0B2B",
          DEFAULT: "#6366F1",
        },
        // Secondary — نارنجی گرم (انرژی + حرکت)
        secondary: {
          50:  "#FFF7ED",
          100: "#FFEDD5",
          200: "#FED7AA",
          300: "#FDBA74",
          400: "#FB923C",
          500: "#F97316",
          600: "#EA580C",
          700: "#C2410C",
          800: "#9A3412",
          900: "#7C2D12",
          DEFAULT: "#F97316",
        },
        // Accent — سبز‌آبی شاد (موفقیت + Trust)
        accent: {
          50:  "#ECFDF5",
          100: "#D1FAE5",
          200: "#A7F3D0",
          300: "#6EE7B7",
          400: "#34D399",
          500: "#10B981",
          600: "#059669",
          700: "#047857",
          800: "#065F46",
          900: "#064E3B",
          DEFAULT: "#10B981",
        },
        // Coral — برای همکاری و calls-to-action
        coral: {
          400: "#FB7185",
          500: "#F43F5E",
          600: "#E11D48",
          DEFAULT: "#F43F5E",
        },
        // Amber — برای هشدار و highlight
        amber: {
          400: "#FBBF24",
          500: "#F59E0B",
          600: "#D97706",
          DEFAULT: "#F59E0B",
        },
        // AI Purple — فقط برای ویژگی‌های هوش مصنوعی
        ai: {
          50:  "#FAF5FF",
          100: "#F3E8FF",
          200: "#E9D5FF",
          300: "#D8B4FE",
          400: "#C084FC",
          500: "#A855F7",
          600: "#9333EA",
          700: "#7E22CE",
          800: "#6B21A8",
          900: "#581C87",
          DEFAULT: "#A855F7",
        },
        // Surface — پس‌زمینه Dark Mode
        surface: {
          50:  "#F8FAFC",
          100: "#F1F5F9",
          200: "#E2E8F0",
          300: "#CBD5E1",
          400: "#94A3B8",
          500: "#64748B",
          600: "#475569",
          700: "#334155",
          800: "#1E293B",
          900: "#0F172A",
          950: "#080F1E",
          DEFAULT: "#1E293B",
        },
        success: "#10B981",
        warning: "#F59E0B",
        error:   "#F43F5E",
        info:    "#6366F1",
      },

      fontFamily: {
        sans: ["var(--font-vazir)", "Tahoma", "Arial", "sans-serif"],
        mono: ["var(--font-mono)", "monospace"],
      },

      borderRadius: {
        "4xl": "2rem",
      },

      keyframes: {
        "fade-in": {
          "0%":   { opacity: "0", transform: "translateY(8px)" },
          "100%": { opacity: "1", transform: "translateY(0)" },
        },
        "slide-up": {
          "0%":   { transform: "translateY(100%)" },
          "100%": { transform: "translateY(0)" },
        },
        shimmer: {
          "0%":   { backgroundPosition: "-200% 0" },
          "100%": { backgroundPosition: "200% 0" },
        },
        pulse_glow: {
          "0%, 100%": { boxShadow: "0 0 0 0 rgba(99,102,241,0.4)" },
          "50%":      { boxShadow: "0 0 0 10px rgba(99,102,241,0)" },
        },
        float: {
          "0%, 100%": { transform: "translateY(0px)" },
          "50%":      { transform: "translateY(-6px)" },
        },
      },
      animation: {
        "fade-in":    "fade-in 0.3s ease-out",
        "slide-up":   "slide-up 0.3s ease-out",
        "shimmer":    "shimmer 2s linear infinite",
        "pulse-glow": "pulse_glow 2s infinite",
        "float":      "float 3s ease-in-out infinite",
      },

      boxShadow: {
        "card-dark":       "0 4px 24px rgba(0,0,0,0.4)",
        "card-glow":       "0 0 20px rgba(99,102,241,0.2)",
        "btn-primary":     "0 4px 14px rgba(99,102,241,0.4)",
        "btn-secondary":   "0 4px 14px rgba(249,115,22,0.4)",
        "btn-coral":       "0 4px 14px rgba(244,63,94,0.4)",
        "glow-purple":     "0 0 30px rgba(168,85,247,0.3)",
      },

      backdropBlur: {
        xs: "2px",
      },
    },
  },
  plugins: [],
};

export default config;
