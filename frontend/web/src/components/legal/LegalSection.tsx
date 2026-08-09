/**
 * قالبِ مشترکِ بخش‌های صفحه‌های حقوقی (قوانین، حریم خصوصی).
 * فقط برای اینکه دو صفحه از هم واگرا نشوند؛ منطقی ندارد.
 */
export default function LegalSection({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mt-7">
      <h2 className="text-base font-bold text-surface-900 dark:text-surface-50">
        {title}
      </h2>
      <div className="mt-2 text-sm leading-7 text-surface-700 dark:text-surface-300">
        {children}
      </div>
    </section>
  );
}
