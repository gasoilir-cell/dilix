"use client";

import AssistantPanel from "@/components/AssistantPanel";

export default function AssistantPage() {
  return (
    <main className="page">
      <h1>دستیار هوشمند</h1>
      <p className="muted">تاریخچه مکالمه‌ها، انتخاب agent و چت پایدار با سرویس AI.</p>
      <AssistantPanel />
    </main>
  );
}
