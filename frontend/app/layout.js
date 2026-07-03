import "./globals.css";
import SplashWrapper from "@/components/SplashWrapper";

export const metadata = {
  title: "FixMyStreet India",
  description: "Report and track civic street grievances",
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>
        <SplashWrapper>{children}</SplashWrapper>
      </body>
    </html>
  );
}
