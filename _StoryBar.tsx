"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Plus, Loader2, Check, Globe, Users, Briefcase, Home, Heart } from "lucide-react";
import toast from "react-hot-toast";
import { storiesApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import MediaEditor from "./MediaEditor";
import StoryViewer, { Ring } from "./StoryViewer";

type Aud = "public" | "followers" | "colleagues" | "family" | "friends";

const AUDIENCE_OPTS: { key: Aud; label: string; desc: string; Icon: typeof Globe }[] = [
  { key: "public", label: "عمومی", desc: "همه می‌توانند ببینند", Icon: Globe },
  { key: "followers", label: "دنبال‌کنندگان", desc: "فقط کسانی که شما را دنبال می‌کنند", Icon: Users },
  { key: "colleagues", label: "همکاران", desc: "فقط حلقهٔ همکاران", Icon: Briefcase },
  { key: "family", label: "خانواده", desc: "فقط حلقهٔ خانواده", Icon: Home },
  { key: "friends", label: "دوستان", desc: "فقط حلقهٔ دوستان", Icon: Heart },
];

export default function StoryBar() {
  const me = useAuthStore((s) => s.user);
  const [rings, setRings] = useState<Ring[]>([]);
  const [loading, setLoading] = useState(true);
  const [viewer, setViewer] = useState<number | null>(null);
  const [editorFile, setEditorFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);

  // انتخابِ مخاطبِ استوری پیش از انتشار
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const [chosenAud, setChosenAud] = useState<Aud>("public");
  const [defaultSet, setDefaultSet] = useState(true); // آیا کاربر قبلاً مخاطبِ پیش‌فرض تعیین کرده؟

  const load = useCallback(async () => {
    try {
      const r = await storiesApi.feed();
      const arr: Ring[] = (r.data || []).map((x: any) => ({
        earth_id: x.earth_id,
        name: x.is_me ? "داستانِ شما" : x.name,
        avatar_url: x.avatar_url,
        is_me: x.is_me,
        has_unseen: x.has_unseen,
      }));
      setRings(arr);
    } catch {
      /* silent */
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  // آیا خودم داستانِ فعال دارم؟
  const myRingIdx = rings.findIndex((r) => r.is_me);
  const hasMyStory = myRingIdx >= 0;

  const onPick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    if (!f.type.startsWith("image/") && !f.type.startsWith("video/")) {
      toast.error("فقط عکس یا ویدیو");
      return;
    }
    setEditorFile(f);
  };

  // پس از اتمامِ ویرایش، مخاطب را می‌پرسیم (با پیش‌فرضِ ذخیره‌شده)
  const onEditorDone = async (file: File) => {
    setEditorFile(null);
    let def: Aud = "public";
    let isSet = true;
    try {
      const r = await storiesApi.settings();
      def = (r.data?.default_audience as Aud) || "public";
      isSet = !!r.data?.is_set;
    } catch {
      /* از پیش‌فرض استفاده کن */
    }
    setChosenAud(def);
    setDefaultSet(isSet);
    setPendingFile(file);
  };

  const publish = async () => {
    if (!pendingFile) return;
    const file = pendingFile;
    const aud = chosenAud;
    const firstTime = !defaultSet;
    setPendingFile(null);
    setUploading(true);
    try {
      await storiesApi.create(file, undefined, file.name, aud);
      // اولین استوری: انتخاب را به‌عنوان مخاطبِ پیش‌فرض ذخیره کن
      if (firstTime) {
        try { await storiesApi.saveSettings(aud); } catch { /* silent */ }
      }
      toast.success("داستانِ شما منتشر شد");
      await load();
    } catch {
      toast.error("انتشار داستان ناموفق بود");
    } finally {
      setUploading(false);
    }
  };

  const markSeen = (earthId: string) => {
    setRings((prev) => prev.map((r) => (r.earth_id === earthId ? { ...r, has_unseen: false } : r)));
  };

  const openViewer = (earthId: string) => {
    const idx = rings.findIndex((r) => r.earth_id === earthId);
    if (idx >= 0) setViewer(idx);
  };

  return (
    <>
      <div className="flex gap-3 overflow-x-auto no-scrollbar px-1 py-2.5 mb-1">
        {/* افزودن داستانِ من */}
        <button
          onClick={() => (hasMyStory ? openViewer(rings[myRingIdx].earth_id) : fileRef.current?.click())}
          className="flex flex-col items-center gap-1 shrink-0 w-[68px]"
        >
          <div className="relative">
            <div
              className={`w-16 h-16 rounded-full p-[2px] ${
                hasMyStory && rings[myRingIdx]?.has_unseen
                  ? "bg-gradient-to-tr from-amber-400 via-rose-500 to-fuchsia-600"
                  : "bg-white/15"
              }`}
            >
              <div className="w-full h-full rounded-full bg-[#141414] p-[2px]">
                <div className="w-full h-full rounded-full bg-white/10 overflow-hidden flex items-center justify-center text-lg">
                  {me?.avatar_url ? (
                    <img src={me.avatar_url} alt="" className="w-full h-full object-cover" />
                  ) : (
                    (me?.full_name?.[0] ?? "👤")
                  )}
                </div>
              </div>
            </div>
            <span className="absolute -bottom-0.5 -left-0.5 w-6 h-6 rounded-full bg-sky-500 border-2 border-[#141414] flex items-center justify-center text-white">
              {uploading ? <Loader2 size={12} className="animate-spin" /> : <Plus size={14} />}
            </span>
          </div>
          <span className="text-[11px] text-white/70 truncate max-w-[64px]">داستانِ شما</span>
        </button>

        {/* رینگ‌های دیگران (و رینگِ خودم اگر جدا لازم بود — اینجا داخلِ همان دکمهٔ بالا لمس می‌شود) */}
        {loading ? (
          <div className="flex items-center px-3">
            <Loader2 size={18} className="text-white/40 animate-spin" />
          </div>
        ) : (
          rings
            .filter((r) => !r.is_me)
            .map((r) => (
              <button
                key={r.earth_id}
                onClick={() => openViewer(r.earth_id)}
                className="flex flex-col items-center gap-1 shrink-0 w-[68px]"
              >
                <div
                  className={`w-16 h-16 rounded-full p-[2px] ${
                    r.has_unseen
                      ? "bg-gradient-to-tr from-amber-400 via-rose-500 to-fuchsia-600"
                      : "bg-white/15"
                  }`}
                >
                  <div className="w-full h-full rounded-full bg-[#141414] p-[2px]">
                    <div className="w-full h-full rounded-full bg-white/10 overflow-hidden flex items-center justify-center text-lg">
                      {r.avatar_url ? (
                        <img src={r.avatar_url} alt="" className="w-full h-full object-cover" />
                      ) : (
                        (r.name?.[0] ?? "👤")
                      )}
                    </div>
                  </div>
                </div>
                <span className="text-[11px] text-white/70 truncate max-w-[64px]">{r.name}</span>
              </button>
            ))
        )}
      </div>

      <input
        ref={fileRef}
        type="file"
        accept="image/*,video/*"
        className="hidden"
        onChange={onPick}
      />

      {editorFile && (
        <MediaEditor
          file={editorFile}
          kind={editorFile.type.startsWith("video/") ? "video" : "image"}
          onCancel={() => setEditorFile(null)}
          onDone={onEditorDone}
        />
      )}

      {/* شیتِ انتخابِ مخاطبِ استوری */}
      {pendingFile && (
        <div className="fixed inset-0 z-[85] flex items-end justify-center bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-md bg-[#1b1b1b] rounded-t-3xl p-5 pb-8 animate-[slideup_.2s_ease]">
            <div className="mx-auto mb-4 h-1 w-10 rounded-full bg-white/20" />
            <h3 className="text-white font-semibold text-center mb-1">این داستان را چه کسانی ببینند؟</h3>
            {!defaultSet && (
              <p className="text-[11px] text-amber-300/80 text-center mb-3">
                این انتخاب به‌عنوان مخاطبِ پیش‌فرضِ شما ذخیره می‌شود (بعداً از تنظیماتِ پروفایل قابل تغییر است).
              </p>
            )}
            <div className="mt-2 space-y-1.5">
              {AUDIENCE_OPTS.map(({ key, label, desc, Icon }) => {
                const active = chosenAud === key;
                return (
                  <button
                    key={key}
                    onClick={() => setChosenAud(key)}
                    className={`w-full flex items-center gap-3 rounded-2xl px-3.5 py-3 text-right transition ${
                      active ? "bg-sky-500/15 ring-1 ring-sky-500" : "bg-white/[0.04] hover:bg-white/[0.07]"
                    }`}
                  >
                    <span className={`shrink-0 w-9 h-9 rounded-full flex items-center justify-center ${active ? "bg-sky-500 text-white" : "bg-white/10 text-white/70"}`}>
                      <Icon size={17} />
                    </span>
                    <span className="flex-1 min-w-0">
                      <span className="block text-sm text-white">{label}</span>
                      <span className="block text-[11px] text-white/50 truncate">{desc}</span>
                    </span>
                    {active && <Check size={18} className="text-sky-400 shrink-0" />}
                  </button>
                );
              })}
            </div>
            <div className="mt-5 flex gap-2.5">
              <button
                onClick={() => setPendingFile(null)}
                className="flex-1 rounded-xl bg-white/[0.06] py-3 text-sm text-white/70"
              >
                انصراف
              </button>
              <button
                onClick={publish}
                className="flex-[2] rounded-xl bg-sky-500 py-3 text-sm font-semibold text-white"
              >
                انتشار داستان
              </button>
            </div>
          </div>
        </div>
      )}

      {viewer !== null && (
        <StoryViewer
          rings={rings}
          startIndex={viewer}
          onClose={() => setViewer(null)}
          onViewed={markSeen}
        />
      )}
    </>
  );
}
