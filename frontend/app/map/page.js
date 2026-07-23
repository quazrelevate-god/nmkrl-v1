import { redirect } from "next/navigation";

// The map is now the app home (app/page.js). Keep this route as a redirect so
// any lingering /map links (e.g. from an old bookmark) still land correctly.
export default function MapPage() {
  redirect("/");
}
