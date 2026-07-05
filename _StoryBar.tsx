"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Plus, Loader2 } from "lucide-react";
import toast from "react-hot-toast";
import { storiesApi } from "@/lib/api";
import { useAuthStore } from "@/store/auth";
import MediaEditor from "./MediaEditor";
import StoryViewer, { Ring } from "./StoryViewer";

export default function StoryBar() {
  const me = useAuthStore((s) => s.user);
  const [rings, setRings] = useState<Ring[]>([]);
  const [loading, setLoading] = useState(true);
  const [viewer, setViewer] = useState<number | null>(null);
  const [editorFile, setEditorFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement | null>(null);

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

  const publish = async (file: File) => {
    setEditorFile(null);
    setUploading(true);
    try {
      await storiesApi.create(file, undefined, file.name);
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

  // ترتیبِ نمایش: دکمهٔ افزودن اول، سپس رینگ‌ها (رینگِ خودم اگر داستان دارد داخلِ لیست است)
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
          onDone={publish}
        />
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
