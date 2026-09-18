import "./globals.css";
import SplashWrapper from "@/components/SplashWrapper";
import ReportProvider from "@/components/ReportProvider";

export const metadata = {
  title: "Project(நம்_குரல்)",
  description: "Namm Kural — a civic voice platform for Tamil Nadu",
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
        <SplashWrapper>
          <ReportProvider>{children}</ReportProvider>
        </SplashWrapper>
      </body>
    </html>
  );
}
