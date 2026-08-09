/**
 * قوانین و مقررات — صفحهٔ عمومی (لینک‌شده از صفحهٔ ورود، پس بدونِ AuthGuard).
 */
import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import LegalSection from "@/components/legal/LegalSection";

export const metadata: Metadata = {
  title: "قوانین و مقررات",
  description: "شرایط استفاده از سرویس دیلیکس.",
};

const UPDATED = "۱۸ مرداد ۱۴۰۵";

export default function TermsPage() {
  return (
    <main className="min-h-screen bg-surface-50 dark:bg-surface-900">
      <div className="mx-auto max-w-3xl px-5 py-10">
        <Link
          href="/login"
          className="inline-flex items-center gap-1.5 text-sm text-primary hover:underline"
        >
          <ArrowRight className="w-4 h-4" />
          بازگشت
        </Link>

        <h1 className="mt-6 text-2xl font-bold text-surface-900 dark:text-surface-50">
          قوانین و مقررات دیلیکس
        </h1>
        <p className="mt-2 text-sm text-surface-500">
          آخرین بازنگری: {UPDATED}
        </p>

        <p className="mt-6 text-sm leading-7 text-surface-700 dark:text-surface-300">
          با ساخت حساب یا استفاده از دیلیکس، شما این شرایط را می‌پذیرید. اگر با
          بخشی از آن موافق نیستید، لطفاً از سرویس استفاده نکنید.
        </p>

        <LegalSection title="۱. حساب کاربری">
          <ul className="list-disc pr-5 space-y-1.5">
            <li>
              هر کاربر یک <b>شناسهٔ زمین (Earth ID)</b> یکتا دریافت می‌کند که شناسهٔ
              عمومی او در سرویس است.
            </li>
            <li>
              اطلاعاتی که هنگام ثبت‌نام یا احراز هویت می‌دهید باید درست و متعلق به
              خودتان باشد.
            </li>
            <li>
              مسئولیت حفظ گذرواژه و دسترسی به حساب با خود شماست. فعال‌کردن ورود
              دومرحله‌ای توصیه می‌شود.
            </li>
            <li>حداقل سن استفاده ۱۳ سال است.</li>
          </ul>
        </LegalSection>

        <LegalSection title="۲. رفتار قابل قبول">
          <p>انجام این کارها ممنوع است و منجر به محدودیت یا مسدودی حساب می‌شود:</p>
          <ul className="mt-2 list-disc pr-5 space-y-1.5">
            <li>انتشار محتوای غیرقانونی، توهین‌آمیز، آزارگر یا نقض‌کنندهٔ حق دیگران.</li>
            <li>جعل هویت دیگران یا استفاده از حساب شخص دیگر.</li>
            <li>ارسال انبوه پیام تبلیغاتی، کلاهبرداری یا هرم‌سازی مالی.</li>
            <li>
              تلاش برای اختلال در سرویس، دسترسی غیرمجاز، یا استخراج خودکار داده
              بدون اجازهٔ کتبی.
            </li>
          </ul>
        </LegalSection>

        <LegalSection title="۳. محتوای کاربر">
          <p>
            مالکیت محتوایی که منتشر می‌کنید متعلق به خودتان است. با انتشار، به ما
            اجازهٔ فنیِ لازم برای ذخیره، نمایش و رساندن آن به مخاطبانی که خودتان
            انتخاب کرده‌اید می‌دهید. ما می‌توانیم محتوای ناقض قوانین را حذف کنیم.
          </p>
        </LegalSection>

        <LegalSection title="۴. حمل بار و معاملات">
          <p>
            دیلیکس بستری برای اتصال طرفین است. قرارداد حمل یا خرید میان
            <b> فرستنده و مجری </b> منعقد می‌شود و مسئولیت اجرای آن با طرفین است.
            در سرویس امانی (escrow)، وجه تا تأیید انجام کار نزد سرویس نگه داشته
            می‌شود؛ در صورت اختلاف، بررسی از مسیر «پشتیبانی» انجام می‌شود.
          </p>
        </LegalSection>

        <LegalSection title="۵. کیف پول و پرداخت">
          <ul className="list-disc pr-5 space-y-1.5">
            <li>
              تراکنش‌ها از طریق درگاه‌های مجاز انجام می‌شود و سوابق آن مطابق قانون
              نگهداری می‌شود.
            </li>
            <li>
              کارمزدها پیش از تأیید هر تراکنش به شما نمایش داده می‌شود.
            </li>
            <li>
              استفاده از سرویس برای پول‌شویی یا هر تراکنش غیرقانونی ممنوع است و به
              مراجع ذی‌صلاح گزارش می‌شود.
            </li>
          </ul>
        </LegalSection>

        <LegalSection title="۶. تماس صوتی و تصویری">
          <p>
            تماس‌ها به‌صورت همتا‌به‌همتا و رمزنگاری‌شده برقرار می‌شوند. ضبط تماس
            بدون اطلاع و رضایت طرف مقابل ممنوع است و ممکن است تخلف قانونی محسوب
            شود.
          </p>
        </LegalSection>

        <LegalSection title="۷. در دسترس بودن سرویس">
          <p>
            سرویس «همان‌گونه که هست» ارائه می‌شود. ما برای پایداری تلاش می‌کنیم اما
            تضمینی برای در دسترس بودن بدون وقفه نمی‌دهیم و ممکن است برای نگهداری،
            بخشی از خدمات موقتاً از دسترس خارج شود.
          </p>
        </LegalSection>

        <LegalSection title="۸. تعلیق و پایان">
          <p>
            در صورت نقض این قوانین، حساب ممکن است محدود یا مسدود شود. شما نیز هر
            زمان می‌توانید از بخش «پشتیبانی» درخواست حذف حساب بدهید.
          </p>
        </LegalSection>

        <LegalSection title="۹. تغییرات">
          <p>
            این قوانین ممکن است به‌روز شود؛ تاریخ بازنگری بالای صفحه تغییر می‌کند و
            ادامهٔ استفاده به‌معنای پذیرش نسخهٔ جدید است.
          </p>
        </LegalSection>

        <LegalSection title="۱۰. تماس">
          <p>
            پرسش یا شکایت:{" "}
            <a href="mailto:support@dilix.ir" className="text-primary hover:underline">
              support@dilix.ir
            </a>
          </p>
        </LegalSection>

        <p className="mt-10 text-sm text-surface-500">
          همچنین ببینید:{" "}
          <Link href="/privacy" className="text-primary hover:underline">
            سیاست حریم خصوصی
          </Link>
        </p>
      </div>
    </main>
  );
}
