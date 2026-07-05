"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  X, Search, Plus, Star, Download, Check, Trash2, Loader2, ArrowRight,
  Globe, FolderPlus, Image as ImageIcon, Play, Volume2, Sticker as StickerIcon,
} from "lucide-react";
import toast from "react-hot-toast";
import { stickersApi } from "@/lib/api";

// ── Types (mirror backend) ───────────────────────────────────
export interface StickerItem {
  id: string;
  pack_id: string;
  media_url: string;
  media_type: "image" | "video" | "voice";
  emoji_tag?: string | null;
  title?: string | null;
  is_starred: boolean;
  created_at: string;
}
export interface StickerPack {
  id: string;
  title: string;
  description?: string | null;
  cover_url?: string | null;
  is_public: boolean;
  is_animated: boolean;
  is_mine: boolean;
  is_installed: boolean;
  install_count: number;
  sticker_count: number;
  owner_name?: string | null;
  created_at: string;
}
interface PackDetail extends StickerPack {
  stickers: StickerItem[];
}

type Tab = "starred" | "mine" | "installed" | "explore";

interface Props {
  onClose: () => void;
  onSendSticker: (stickerId: string) => void;
  initialPackId?: string | null;
}

// ── Media thumbnail ──────────────────────────────────────────
function StickerThumb({ s }: { s: StickerItem }) {
  if (s.media_type === "video") {
    return (
      <div className="relative w-full h-full">
        <video src={s.media_url} muted loop playsInline className="w-full h-full object-contain rounded-lg" />
        <span className="absolute bottom-0.5 left-0.5 bg-black/50 rounded-full p-0.5">
          <Play size={9} className="text-white" />
        </span>
      </div>
    );
  }
  if (s.media_type === "voice") {
    return (
      <div className="w-full h-full flex items-center justify-center bg-white/5 rounded-lg">
        <Volume2 size={22} className="text-fuchsia-300" />
        {s.emoji_tag && <span className="absolute text-lg">{s.emoji_tag}</span>}
      </div>
    );
  }
  return <img src={s.media_url} alt={s.title ?? ""} className="w-full h-full object-contain rounded-lg" />;
}

export default function StickerLibrary({ onClose, onSendSticker, initialPackId }: Props) {
  const [tab, setTab] = useState<Tab>("starred");
  const [loading, setLoading] = useState(false);

  const [starred, setStarred] = useState<StickerItem[]>([]);
  const [minePacks, setMinePacks] = useState<StickerPack[]>([]);
  const [installed, setInstalled] = useState<StickerPack[]>([]);
  const [publicPacks, setPublicPacks] = useState<StickerPack[]>([]);
  const [query, setQuery] = useState("");

  const [detail, setDetail] = useState<PackDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const [creating, setCreating] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [newPublic, setNewPublic] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const addTargetRef = useRef<string | null>(null);

  // ── loaders ────────────────────────────────────────────────
  const loadStarred = useCallback(async () => {
    setLoading(true);
    try { setStarred((await stickersApi.starred()).data); }
    catch { /* ignore */ } finally { setLoading(false); }
  }, []);
  const loadMine = useCallback(async () => {
    setLoading(true);
    try { setMinePacks((await stickersApi.myPacks()).data); }
    catch { /* ignore */ } finally { setLoading(false); }
  }, []);
  const loadInstalled = useCallback(async () => {
    setLoading(true);
    try { setInstalled((await stickersApi.installedPacks()).data); }
    catch { /* ignore */ } finally { setLoading(false); }
  }, []);
  const loadPublic = useCallback(async (q?: string) => {
    setLoading(true);
    try { setPublicPacks((await stickersApi.publicPacks(q)).data); }
    catch { /* ignore */ } finally { setLoading(false); }
  }, []);

  const openDetail = useCallback(async (packId: string) => {
    setDetailLoading(true);
    try { setDetail((await stickersApi.packDetail(packId)).data); }
    catch { toast.error("بارگذاریِ بسته ناموفق بود"); }
    finally { setDetailLoading(false); }
  }, []);

  // initial
  useEffect(() => {
    if (initialPackId) { openDetail(initialPackId); return; }
    loadStarred();
  }, [initialPackId, openDetail, loadStarred]);

  // tab switches
  useEffect(() => {
    if (detail) return;
    if (tab === "starred") loadStarred();
    else if (tab === "mine") loadMine();
    else if (tab === "installed") loadInstalled();
    else if (tab === "explore") loadPublic(query.trim() || undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab]);

  // search (debounced) for explore
  useEffect(() => {
    if (tab !== "explore" || detail) return;
    const t = setTimeout(() => loadPublic(query.trim() || undefined), 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  // ── actions ────────────────────────────────────────────────
  const send = (s: StickerItem) => { onSendSticker(s.id); onClose(); };

  const toggleStar = async (s: StickerItem) => {
    const next = !s.is_starred;
    // optimistic in detail + starred list
    setDetail(d => d ? { ...d, stickers: d.stickers.map(x => x.id === s.id ? { ...x, is_starred: next } : x) } : d);
    setStarred(prev => next ? prev : prev.filter(x => x.id !== s.id));
    try {
      if (next) { await stickersApi.star(s.id); if (tab === "starred" && !detail) loadStarred(); }
      else await stickersApi.unstar(s.id);
    } catch { toast.error("عملیات ناموفق بود"); }
  };

  const installToggle = async (p: StickerPack) => {
    const next = !p.is_installed;
    const patch = (arr: StickerPack[]) => arr.map(x => x.id === p.id ? { ...x, is_installed: next, install_count: x.install_count + (next ? 1 : -1) } : x);
    setPublicPacks(patch);
    setDetail(d => d && d.id === p.id ? { ...d, is_installed: next } : d);
    try {
      if (next) { await stickersApi.install(p.id); toast.success("به کتابخانه‌ی شما افزوده شد"); }
      else await stickersApi.uninstall(p.id);
    } catch { toast.error("عملیات ناموفق بود"); }
  };

  const createPack = async () => {
    if (!newTitle.trim()) return;
    try {
      const res = await stickersApi.createPack(newTitle.trim(), undefined, newPublic);
      setCreating(false); setNewTitle(""); setNewPublic(false);
      toast.success("بسته ساخته شد");
      await loadMine();
      openDetail(res.data.id);
    } catch { toast.error("ساختِ بسته ناموفق بود"); }
  };

  const pickAddSticker = (packId: string) => {
    addTargetRef.current = packId;
    fileRef.current?.click();
  };
  const onFilePicked = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    const packId = addTargetRef.current;
    if (!f || !packId) return;
    const tid = toast.loading("در حالِ افزودن...");
    try {
      await stickersApi.addSticker(packId, f, { filename: f.name });
      toast.success("افزوده شد", { id: tid });
      openDetail(packId);
      loadMine();
    } catch { toast.error("افزودن ناموفق بود", { id: tid }); }
  };

  const deleteSticker = async (s: StickerItem) => {
    setDetail(d => d ? { ...d, stickers: d.stickers.filter(x => x.id !== s.id) } : d);
    try { await stickersApi.deleteSticker(s.id); } catch { toast.error("حذف ناموفق بود"); }
  };

  const deletePack = async (p: PackDetail) => {
    if (!confirm(`بسته‌ی «${p.title}» حذف شود؟`)) return;
    try {
      await stickersApi.deletePack(p.id);
      setDetail(null); loadMine();
      toast.success("بسته حذف شد");
    } catch { toast.error("حذف ناموفق بود"); }
  };

  // ── UI pieces ──────────────────────────────────────────────
  const Grid = ({ items, editable }: { items: StickerItem[]; editable?: boolean }) => (
    <div className="grid grid-cols-4 gap-2">
      {items.map((s) => (
        <div key={s.id} className="relative aspect-square group">
          <button
            onClick={() => send(s)}
            className="w-full h-full rounded-lg bg-white/[0.03] hover:bg-white/10 flex items-center justify-center p-1 relative"
          >
            <StickerThumb s={s} />
          </button>
          <button
            onClick={() => toggleStar(s)}
            className="absolute -top-1.5 -right-1.5 w-6 h-6 rounded-full bg-[#1C1C1E] border border-white/10 flex items-center justify-center"
          >
            <Star size={13} className={s.is_starred ? "text-amber-400 fill-amber-400" : "text-white/40"} />
          </button>
          {editable && (
            <button
              onClick={() => deleteSticker(s)}
              className="absolute -bottom-1.5 -right-1.5 w-6 h-6 rounded-full bg-[#1C1C1E] border border-white/10 flex items-center justify-center"
            >
              <Trash2 size={12} className="text-red-400" />
            </button>
          )}
        </div>
      ))}
    </div>
  );

  const PackCard = ({ p }: { p: StickerPack }) => (
    <button
      onClick={() => openDetail(p.id)}
      className="w-full flex items-center gap-3 p-2.5 rounded-2xl bg-white/[0.03] hover:bg-white/[0.06] text-right"
    >
      <span className="w-14 h-14 rounded-xl bg-white/5 flex items-center justify-center overflow-hidden shrink-0">
        {p.cover_url ? <img src={p.cover_url} alt="" className="w-full h-full object-contain" /> : <StickerIcon size={22} className="text-white/30" />}
      </span>
      <span className="flex-1 min-w-0">
        <span className="block text-white text-sm font-semibold truncate">{p.title}</span>
        <span className="block text-white/40 text-xs truncate">
          {p.sticker_count} استیکر{p.owner_name ? ` · ${p.owner_name}` : ""}{p.is_animated ? " · متحرک" : ""}
        </span>
      </span>
      {p.is_public && !p.is_mine && (
        <span
          onClick={(e) => { e.stopPropagation(); installToggle(p); }}
          className={`shrink-0 flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-medium ${
            p.is_installed ? "bg-emerald-500/15 text-emerald-300" : "bg-indigo-500/20 text-indigo-200"
          }`}
        >
          {p.is_installed ? <><Check size={13} /> نصب‌شده</> : <><Download size={13} /> نصب</>}
        </span>
      )}
    </button>
  );

  // ── Detail view ────────────────────────────────────────────
  if (detail || detailLoading) {
    return (
      <div className="fixed inset-0 z-[60] flex items-end justify-center bg-black/60" onClick={onClose}>
        <div className="w-full max-w-md bg-[#141414] rounded-t-3xl max-h-[85vh] flex flex-col animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
          <div className="flex items-center gap-2 p-4 border-b border-white/8">
            <button onClick={() => setDetail(null)} className="p-1.5 rounded-lg hover:bg-white/5 text-white/60"><ArrowRight size={18} /></button>
            <div className="flex-1 min-w-0">
              <p className="text-white font-bold truncate">{detail?.title ?? "..."}</p>
              {detail && (
                <p className="text-white/40 text-xs truncate">
                  {detail.sticker_count} استیکر{detail.owner_name ? ` · ${detail.owner_name}` : ""}
                  {detail.install_count > 0 ? ` · ${detail.install_count} نصب` : ""}
                </p>
              )}
            </div>
            {detail && detail.is_public && !detail.is_mine && (
              <button
                onClick={() => installToggle(detail)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium ${
                  detail.is_installed ? "bg-emerald-500/15 text-emerald-300" : "bg-indigo-500/20 text-indigo-200"
                }`}
              >
                {detail.is_installed ? <><Check size={14} /> نصب‌شده</> : <><Download size={14} /> نصب</>}
              </button>
            )}
            {detail?.is_mine && (
              <>
                <button onClick={() => pickAddSticker(detail.id)} className="p-2 rounded-full bg-fuchsia-500/15 text-fuchsia-300"><Plus size={16} /></button>
                <button onClick={() => deletePack(detail)} className="p-2 rounded-full hover:bg-white/5 text-red-400"><Trash2 size={16} /></button>
              </>
            )}
            <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-white/5 text-white/50"><X size={18} /></button>
          </div>
          <div className="flex-1 overflow-y-auto p-4">
            {detailLoading || !detail ? (
              <div className="py-16 flex justify-center"><Loader2 className="animate-spin text-white/40" /></div>
            ) : detail.stickers.length === 0 ? (
              <div className="py-14 text-center text-white/40 text-sm">
                <StickerIcon size={34} className="mx-auto mb-2 opacity-40" />
                هنوز استیکری نیست.
                {detail.is_mine && <p className="mt-1">با دکمهٔ + استیکر اضافه کنید.</p>}
              </div>
            ) : (
              <Grid items={detail.stickers} editable={detail.is_mine} />
            )}
          </div>
        </div>
        <input ref={fileRef} type="file" accept="image/*,video/*,audio/*" className="hidden" onChange={onFilePicked} />
      </div>
    );
  }

  // ── Main list view ─────────────────────────────────────────
  const TABS: { k: Tab; label: string; icon: React.ReactNode }[] = [
    { k: "starred", label: "ستاره‌دار", icon: <Star size={15} /> },
    { k: "mine", label: "کتابخانه‌ی من", icon: <StickerIcon size={15} /> },
    { k: "installed", label: "نصب‌شده", icon: <Download size={15} /> },
    { k: "explore", label: "کاوش", icon: <Globe size={15} /> },
  ];

  return (
    <div className="fixed inset-0 z-[60] flex items-end justify-center bg-black/60" onClick={onClose}>
      <div className="w-full max-w-md bg-[#141414] rounded-t-3xl max-h-[85vh] flex flex-col animate-[slideUp_0.2s_ease]" onClick={(e) => e.stopPropagation()}>
        {/* header */}
        <div className="flex items-center justify-between px-4 pt-4 pb-2">
          <p className="text-white font-bold">کتابخانهٔ استیکر و ایموجی</p>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-white/5 text-white/50"><X size={18} /></button>
        </div>
        {/* tabs */}
        <div className="flex gap-1 px-3 pb-2 overflow-x-auto">
          {TABS.map((t) => (
            <button
              key={t.k}
              onClick={() => setTab(t.k)}
              className={`shrink-0 flex items-center gap-1.5 px-3 py-2 rounded-full text-xs font-medium border ${
                tab === t.k ? "bg-fuchsia-500/15 border-fuchsia-400/40 text-white" : "bg-white/5 border-white/8 text-white/70 hover:bg-white/10"
              }`}
            >
              {t.icon}{t.label}
            </button>
          ))}
        </div>

        {/* search (explore) */}
        {tab === "explore" && (
          <div className="px-4 pb-2">
            <div className="flex items-center gap-2 bg-white/5 rounded-xl px-3 py-2">
              <Search size={16} className="text-white/40" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="جست‌وجوی کتابخانه‌های عمومی..."
                className="flex-1 bg-transparent text-sm text-white placeholder:text-white/30 outline-none"
              />
            </div>
          </div>
        )}

        {/* content */}
        <div className="flex-1 overflow-y-auto px-4 pb-4">
          {loading ? (
            <div className="py-16 flex justify-center"><Loader2 className="animate-spin text-white/40" /></div>
          ) : tab === "starred" ? (
            starred.length === 0 ? (
              <Empty icon={<Star size={34} />} text="هنوز استیکرِ ستاره‌داری ندارید. با لمسِ ⭐ روی هر استیکر آن را اینجا نگه دارید." />
            ) : <Grid items={starred} />
          ) : tab === "mine" ? (
            <div className="space-y-2">
              <button
                onClick={() => setCreating(true)}
                className="w-full flex items-center gap-3 p-3 rounded-2xl border border-dashed border-white/15 text-white/80 hover:bg-white/5 text-sm"
              >
                <span className="w-10 h-10 rounded-xl bg-fuchsia-500/15 flex items-center justify-center"><FolderPlus size={18} className="text-fuchsia-300" /></span>
                ساختِ بستهٔ جدید
              </button>
              {minePacks.map((p) => <PackCard key={p.id} p={p} />)}
              {minePacks.length === 0 && <p className="text-white/30 text-xs text-center py-6">هنوز بسته‌ای نساخته‌اید.</p>}
            </div>
          ) : tab === "installed" ? (
            installed.length === 0 ? (
              <Empty icon={<Download size={34} />} text="بسته‌ای نصب نکرده‌اید. از تبِ «کاوش» کتابخانه‌های دیگران را نصب کنید." />
            ) : <div className="space-y-2">{installed.map((p) => <PackCard key={p.id} p={p} />)}</div>
          ) : (
            publicPacks.length === 0 ? (
              <Empty icon={<Globe size={34} />} text={query ? "کتابخانه‌ای یافت نشد." : "هنوز کتابخانهٔ عمومی‌ای منتشر نشده است."} />
            ) : <div className="space-y-2">{publicPacks.map((p) => <PackCard key={p.id} p={p} />)}</div>
          )}
        </div>
      </div>

      {/* create pack sheet */}
      {creating && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-6" onClick={() => setCreating(false)}>
          <div className="w-full max-w-sm bg-[#1C1C1E] rounded-2xl p-4" onClick={(e) => e.stopPropagation()}>
            <p className="text-white font-bold mb-3">بستهٔ جدید</p>
            <input
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              maxLength={120}
              placeholder="نامِ بسته"
              className="w-full bg-white/5 rounded-xl px-3 py-2.5 text-sm text-white placeholder:text-white/30 outline-none mb-3"
            />
            <label className="flex items-center gap-2 text-sm text-white/80 mb-4">
              <input type="checkbox" checked={newPublic} onChange={(e) => setNewPublic(e.target.checked)} className="accent-fuchsia-500" />
              عمومی — دیگران بتوانند پیدا و نصب کنند
            </label>
            <div className="flex gap-2">
              <button onClick={() => setCreating(false)} className="flex-1 py-2.5 rounded-xl bg-white/5 text-white/70 text-sm">انصراف</button>
              <button onClick={createPack} disabled={!newTitle.trim()} className="flex-1 py-2.5 rounded-xl bg-fuchsia-500/90 disabled:opacity-40 text-white text-sm font-medium">ساختن</button>
            </div>
          </div>
        </div>
      )}

      <input ref={fileRef} type="file" accept="image/*,video/*,audio/*" className="hidden" onChange={onFilePicked} />
    </div>
  );
}

function Empty({ icon, text }: { icon: React.ReactNode; text: string }) {
  return (
    <div className="py-16 text-center text-white/40 text-sm px-6">
      <div className="mx-auto mb-3 opacity-40 flex justify-center">{icon}</div>
      {text}
    </div>
  );
}
