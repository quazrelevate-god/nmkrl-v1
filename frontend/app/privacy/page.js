/**
 * Public privacy policy for the நம்குரல் / Nam Kural Connect citizen app.
 *
 * Required by Google Play because the app uses location, the microphone,
 * photos and a phone number, and by India's DPDP Act. Linked from the app's
 * profile screen and from the Play Store listing.
 *
 * The content is accurate to what the app actually does today. The one thing
 * the operator MUST fill before publishing is the CONTACT block below
 * (marked TODO): the legal entity running the service and a working email.
 */

export const metadata = {
  title: "Privacy Policy · Nam Kural Connect",
  description: "How the Nam Kural Connect civic grievance app collects, uses and protects your data.",
};

const UPDATED = "13 September 2026";

// TODO(operator): replace with the real operating entity and a working contact.
const OPERATOR = "the Nam Kural Connect team";
const CONTACT_EMAIL = "privacy@nammakural.example"; // TODO(operator): real address

function Section({ title, children }) {
  return (
    <section className="mt-8">
      <h2 className="text-lg font-bold text-slate-900">{title}</h2>
      <div className="mt-2 space-y-3 text-[15px] leading-relaxed text-slate-700">
        {children}
      </div>
    </section>
  );
}

export default function PrivacyPolicyPage() {
  return (
    <main className="mx-auto max-w-2xl px-5 py-12 sm:py-16">
      <p className="text-[13px] font-bold uppercase tracking-wider text-brand">Nam Kural Connect · நம்குரல்</p>
      <h1 className="mt-1 text-3xl font-extrabold text-slate-900">Privacy Policy</h1>
      <p className="mt-2 text-sm text-slate-500">Last updated: {UPDATED}</p>

      <p className="mt-6 text-[15px] leading-relaxed text-slate-700">
        Nam Kural Connect is a civic grievance app for Chennai. It lets residents report
        street-level problems — potholes, drainage, streetlights and the like — to
        the officials responsible for fixing them, and follow what happens next.
        This policy explains what the app collects, why, who it is shared with, and
        the control you have over it.
      </p>

      <Section title="Information we collect">
        <p>We collect only what the app needs to register your grievance and keep you updated:</p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><b>Your name and mobile number</b>, to create your account and let officials reach you about your report. Your number is verified by a one-time SMS code at sign-in.</li>
          <li><b>Precise location</b>, when you file a report, so the grievance is placed on the map and routed to the correct ward. Location is used only while the app is open; there is no background tracking.</li>
          <li><b>Photos, a voice note, and any document</b> you attach to a grievance to describe the problem.</li>
          <li><b>The text and details of your grievance</b>, including a transcript of your voice note.</li>
          <li><b>A device notification token</b>, so we can send you push updates about your report.</li>
        </ul>
      </Section>

      <Section title="How we use your information">
        <ul className="list-disc space-y-1.5 pl-5">
          <li>To register your grievance and route it to the responsible department and officer.</li>
          <li>To show verified grievances on a public neighbourhood map so residents can see and support local issues.</li>
          <li>To notify you when the status of your report changes, and to let you confirm or reject a resolution.</li>
          <li>To transcribe and summarise your voice note and any attached document, so officials can act on it quickly.</li>
        </ul>
      </Section>

      <Section title="What is shown publicly">
        <p>
          A grievance that has been verified appears on a public ward map that any
          resident can see. This includes the problem&apos;s photo, location, description
          and how many people have supported it. It does <b>not</b> include your name,
          your phone number, or anything that identifies you — those are visible only
          to you and to the officials handling your report.
        </p>
      </Section>

      <Section title="Who we share it with">
        <p>We do not sell your data. We share it only to make the app work:</p>
        <ul className="list-disc space-y-1.5 pl-5">
          <li><b>Government officials and staff</b> responsible for your grievance, who see your report and contact details in order to act on it.</li>
          <li><b>Google</b> — your voice note and any attached document are processed by Google&apos;s Gemini AI to produce a transcript and summary, and push notifications are delivered through Google Firebase Cloud Messaging.</li>
          <li><b>Our SMS provider</b>, to send the one-time verification code to your number.</li>
          <li><b>Map data</b> is provided by OpenStreetMap; approximate place names come from its geocoding service.</li>
        </ul>
      </Section>

      <Section title="How long we keep it, and deleting your account">
        <p>
          You can delete your account at any time, from <b>Profile → Delete account</b>
          in the app, or from the web at{" "}
          <a className="font-semibold text-brand underline" href="/account/delete">this deletion page</a>.
        </p>
        <p>
          When you delete your account, we permanently remove your name, phone number,
          voice recordings and their transcripts, and any document you attached. The
          grievances you filed remain as anonymous civic records — stripped of anything
          that identifies you — because the officials handling them still need the
          problem, its photo and its location to fix it.
        </p>
      </Section>

      <Section title="How we protect it">
        <p>
          All data is encrypted in transit (HTTPS). Your app can be locked with a
          4-digit PIN, which is stored only on your device as a one-way hash and never
          sent to us in the clear.
        </p>
      </Section>

      <Section title="Your rights">
        <p>
          Under India&apos;s Digital Personal Data Protection Act, you may ask to access,
          correct, or delete your personal data. You can delete your data yourself using
          the options above, or contact us for anything else.
        </p>
      </Section>

      <Section title="Children">
        <p>
          Nam Kural Connect is intended for adult residents reporting civic issues. It is not
          directed at children.
        </p>
      </Section>

      <Section title="Contact">
        <p>
          Questions about this policy or your data can be sent to {OPERATOR} at{" "}
          <a className="font-semibold text-brand underline" href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
        </p>
      </Section>

      <Section title="Changes to this policy">
        <p>
          We may update this policy as the app changes. The date at the top shows when
          it was last revised.
        </p>
      </Section>

      <footer className="mt-12 border-t border-slate-200 pt-6 text-[13px] text-slate-400">
        Nam Kural Connect · நம்குரல் — a civic voice platform for Tamil Nadu.
      </footer>
    </main>
  );
}
