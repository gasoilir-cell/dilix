"use client";

import { useState, useEffect } from "react";
import AppShell from "@/components/layout/AppShell";
import {
  Truck, Package, MapPin, Weight, Plus,
  Clock, CheckCircle2, AlertCircle, ChevronLeft,
  ArrowLeft, X, DollarSign, Calendar,
} from "lucide-react";
import { useAuthStore } from "@/store/auth";
import { toPersianNum, formatAmount } from "@/lib/utils";
import toast from "react-hot-toast";

// ── Types ─────────────────────────────────────────────────────
interface CargoPost {
  id:          string;
  ref:         string;
  owner_id:    string;
  origin:      string;
  destination: string;
  cargo_type:  string;
  weight_kg:   number;
  price:       number;
  description: string | null;
  status:      "open" | "in_progress" | "delivered" | "cancelled";
  driver_id:   string | null;
  created_at:  string;
}

const STATUS = {
  open:        { label: "در انتظار راننده", color: "#F59E0B", icon: Clock },
  in_progress: { label: "در مسیر",          color: "#6366F1", icon: Truck },
  delivered:   { label: "تحویل شد",         color: "#10B981", icon: CheckCircle2 },
  cancelled:   { label: "لغو شده",          color: "#F43F5E", icon: AlertCircle },
};

const CARGO_TYPES = [
  "لوازم الکترونیک","مواد غذایی","منسوجات","مواد شیمیایی",
  "ماشین‌آلات","پوشاک","مصالح ساختمانی","سایر",
];

const API = process.env.NEXT_PUBLIC_API_URL ?? "https://dilix.ir/api/v1";

// ── Component ─────────────────────────────────────────────────
export default function FreightPage() {
  const user  = useAuthStore((s) => s.user);
  const token = useAuthStore((s) => s.accessToken);
  const role  = user?.role ?? "user";
  const isDriver = role === "driver";

  const [posts,      setPosts]      = useState<CargoPost[]>([]);
  const [myPosts,    setMyPosts]    = useState<CargoPost[]>([]);
  const [loading,    setLoading]    = useState(false);
  const [activeTab,  setActiveTab]  = useState<"list" | "mine" | "new">(isDriver ? "list" : "mine");
  const [showForm,   setShowForm]   = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // Form state
  const [form, setForm] = useState({
    origin: "", destination: "", cargo_type: "", weight_kg: "",
    price: "", description: "", pickup_date: "",
  });

  // ── Fetch ──────────────────────────────────────────────────
  const fetchPosts = async (mine = false) => {
    setLoading(true);
    try {
      const res = await fetch(
        `${API}/freight/posts${mine ? "?mine=true" : ""}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      if (!res.ok) throw new Error();
      const data = await res.json();
      if (mine) setMyPosts(data);
      else      setPosts(data);
    } catch {
      // اگر backend آفلاین بود، داده نمایشی نشان می‌دهیم
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (token) {
      fetchPosts(false);
      if (!isDriver) fetchPosts(true);
    }
  }, [token]);

  // ── Submit new post ────────────────────────────────────────
  const submitPost = async () => {
    if (!form.origin || !form.destination || !form.cargo_type || !form.weight_kg || !form.price) {
      toast.error("لطفاً همه فیلدهای ضروری را پر کن");
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`${API}/freight/posts`, {
        method:  "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          origin:      form.origin,
          destination: form.destination,
          cargo_type:  form.cargo_type,
          weight_kg:   parseFloat(form.weight_kg),
          price:       parseInt(form.price.replace(/,/g, "")),
          description: form.description || null,
          pickup_date: form.pickup_date || null,
        }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.detail || "خطا");
      }
      const newPost = await res.json();
      setMyPosts((prev) => [newPost, ...prev]);
      setForm({ origin:"", destination:"", cargo_type:"", weight_kg:"", price:"", description:"", pickup_date:"" });
      setShowForm(false);
      setActiveTab("mine");
      toast.success("بار با موفقیت ثبت شد ✓");
    } catch (e: unknown) {
      toast.error((e as Error).message || "خطا در ثبت بار");
    } finally {
      setSubmitting(false);
    }
  };

  // ── Take cargo (driver) ────────────────────────────────────
  const takePost = async (postId: string) => {
    try {
      const res = await fetch(`${API}/freight/posts/${postId}/take`, {
        method:  "POST",
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) { const e = await res.json(); throw new Error(e.detail); }
      setPosts((prev) => prev.filter((p) => p.id !== postId));
      toast.success("بار پذیرفته شد! اطلاعات صاحب بار ارسال می‌شود ✓");
    } catch (e: unknown) {
      toast.error((e as Error).message || "خطا");
    }
  };

  // ── Styles ─────────────────────────────────────────────────
  const card = {
    background: "#1C1C1E",
    border:     "1px solid rgba(255,255,255,0.08)",
    borderRadius: "16px",
  };

  return (
    <AppShell title="حمل بار" showSearch={false}>
      <div className="px-4 pt-4 pb-6 space-y-4">

        {/* ── Tabs ── */}
        <div
          className="flex rounded-2xl p-1"
          style={{ background: "#1C1C1E" }}
        >
          {isDriver ? (
            <TabBtn label="بارهای موجود" icon={<Truck size={14}/>} active={activeTab==="list"} onClick={()=>setActiveTab("list")} />
          ) : (
            <>
              <TabBtn label="بارهای من" icon={<Package size={14}/>} active={activeTab==="mine"} onClick={()=>setActiveTab("mine")} />
              <TabBtn label="همه بارها" icon={<Truck size={14}/>} active={activeTab==="list"} onClick={()=>setActiveTab("list")} />
            </>
          )}
        </div>

        {/* ── Stats (driver) ── */}
        {isDriver && (
          <div className="grid grid-cols-3 gap-3">
            {[
              { label:"سفرها",   value: toPersianNum(user?.total_trips ?? 0), color:"#F97316" },
              { label:"موجود",   value: toPersianNum(posts.length),            color:"#10B981" },
              { label:"امتیاز",  value: "—",                                   color:"#6366F1" },
            ].map((s) => (
              <div key={s.label} style={{ ...card, padding:"12px", textAlign:"center" }}>
                <p className="text-lg font-black text-white">{s.value}</p>
                <p className="text-[11px]" style={{ color:"rgba(255,255,255,0.4)" }}>{s.label}</p>
              </div>
            ))}
          </div>
        )}

        {/* ── New post button (owner) ── */}
        {!isDriver && !showForm && (
          <button
            onClick={() => setShowForm(true)}
            className="w-full py-3 rounded-2xl font-bold text-white flex items-center justify-center gap-2 active:scale-95 transition-all"
            style={{ background:"linear-gradient(135deg,#06B6D4,#6366F1)", boxShadow:"0 4px 16px rgba(6,182,212,0.35)" }}
          >
            <Plus size={20} />
            ثبت بار جدید
          </button>
        )}

        {/* ── New post form ── */}
        {showForm && (
          <div style={{ ...card, padding:"20px" }} className="space-y-3">
            <div className="flex items-center justify-between mb-2">
              <h3 className="font-bold text-white">ثبت بار جدید</h3>
              <button onClick={() => setShowForm(false)} style={{ color:"rgba(255,255,255,0.4)" }}>
                <X size={20} />
              </button>
            </div>

            {[
              { key:"origin",      label:"مبدأ",      placeholder:"مثلاً: تهران، بازار بزرگ" },
              { key:"destination", label:"مقصد",      placeholder:"مثلاً: اصفهان، شهرک صنعتی" },
            ].map((f) => (
              <div key={f.key}>
                <label className="text-xs font-medium mb-1 block" style={{ color:"rgba(255,255,255,0.6)" }}>
                  {f.label} <span className="text-red-400">*</span>
                </label>
                <input
                  className="input w-full"
                  placeholder={f.placeholder}
                  value={(form as never)[f.key]}
                  onChange={(e) => setForm((p) => ({ ...p, [f.key]: e.target.value }))}
                />
              </div>
            ))}

            <div>
              <label className="text-xs font-medium mb-1 block" style={{ color:"rgba(255,255,255,0.6)" }}>
                نوع بار <span className="text-red-400">*</span>
              </label>
              <div className="flex gap-2 flex-wrap">
                {CARGO_TYPES.map((t) => (
                  <button
                    key={t}
                    onClick={() => setForm((p) => ({ ...p, cargo_type: t }))}
                    className="text-xs px-3 py-1.5 rounded-full transition-all"
                    style={{
                      background: form.cargo_type===t ? "rgba(99,102,241,0.3)" : "rgba(255,255,255,0.06)",
                      border:     `1px solid ${form.cargo_type===t ? "#6366F1" : "rgba(255,255,255,0.08)"}`,
                      color:      form.cargo_type===t ? "#818CF8" : "rgba(255,255,255,0.55)",
                    }}
                  >
                    {t}
                  </button>
                ))}
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-medium mb-1 block" style={{ color:"rgba(255,255,255,0.6)" }}>
                  وزن (کیلوگرم) <span className="text-red-400">*</span>
                </label>
                <input
                  className="input w-full ltr text-left"
                  type="number"
                  placeholder="500"
                  value={form.weight_kg}
                  onChange={(e) => setForm((p) => ({ ...p, weight_kg: e.target.value }))}
                />
              </div>
              <div>
                <label className="text-xs font-medium mb-1 block" style={{ color:"rgba(255,255,255,0.6)" }}>
                  قیمت (ریال) <span className="text-red-400">*</span>
                </label>
                <input
                  className="input w-full ltr text-left"
                  type="number"
                  placeholder="5000000"
                  value={form.price}
                  onChange={(e) => setForm((p) => ({ ...p, price: e.target.value }))}
                />
              </div>
            </div>

            <div>
              <label className="text-xs font-medium mb-1 block" style={{ color:"rgba(255,255,255,0.6)" }}>
                توضیحات (اختیاری)
              </label>
              <textarea
                className="input w-full resize-none"
                rows={2}
                placeholder="جزئیات بیشتر..."
                value={form.description}
                onChange={(e) => setForm((p) => ({ ...p, description: e.target.value }))}
              />
            </div>

            <button
              onClick={submitPost}
              disabled={submitting}
              className="w-full py-3 rounded-2xl font-bold text-white active:scale-95 transition-all disabled:opacity-60"
              style={{ background:"linear-gradient(135deg,#06B6D4,#6366F1)" }}
            >
              {submitting ? "در حال ثبت..." : "ثبت بار"}
            </button>
          </div>
        )}

        {/* ── List of posts ── */}
        {loading ? (
          <div className="space-y-3">
            {[1,2,3].map((n) => (
              <div key={n} className="h-28 rounded-2xl animate-pulse" style={{ background:"#1C1C1E" }} />
            ))}
          </div>
        ) : (
          <div className="space-y-3">
            {(activeTab === "mine" ? myPosts : posts).length === 0 ? (
              <EmptyState isDriver={isDriver} onNew={() => setShowForm(true)} />
            ) : (
              (activeTab === "mine" ? myPosts : posts).map((post) => (
                <PostCard
                  key={post.id}
                  post={post}
                  isDriver={isDriver}
                  onTake={takePost}
                />
              ))
            )}
          </div>
        )}

      </div>
    </AppShell>
  );
}

// ── Tab button ────────────────────────────────────────────────
function TabBtn({ label, icon, active, onClick }: {
  label: string; icon: React.ReactNode; active: boolean; onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-xl text-sm font-semibold transition-all"
      style={{
        background: active ? "#6366F1" : "transparent",
        color:      active ? "#fff" : "rgba(255,255,255,0.45)",
        boxShadow:  active ? "0 2px 8px rgba(99,102,241,0.4)" : "none",
      }}
    >
      {icon} {label}
    </button>
  );
}

// ── Post card ─────────────────────────────────────────────────
function PostCard({ post, isDriver, onTake }: {
  post: CargoPost; isDriver: boolean; onTake: (id: string) => void;
}) {
  const s = STATUS[post.status] ?? STATUS.open;
  const SIcon = s.icon;

  return (
    <div
      className="rounded-2xl p-4"
      style={{ background:"#1C1C1E", border:"1px solid rgba(255,255,255,0.07)" }}
    >
      <div className="flex items-start justify-between mb-3">
        <div>
          <p className="text-xs font-mono" style={{ color:"rgba(255,255,255,0.35)" }}>{post.ref}</p>
          <div className="flex items-center gap-1.5 mt-1">
            <SIcon size={13} style={{ color: s.color }} />
            <span className="text-xs font-semibold" style={{ color: s.color }}>{s.label}</span>
          </div>
        </div>
        <p className="text-base font-black text-white">{formatAmount(post.price)}</p>
      </div>

      <div className="space-y-1.5 mb-3">
        <div className="flex items-center gap-2">
          <div className="w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background:"rgba(99,102,241,0.2)" }}>
            <MapPin size={11} style={{ color:"#818CF8" }} />
          </div>
          <p className="text-sm text-white truncate">{post.origin}</p>
        </div>
        <div className="flex items-center gap-2 pr-2">
          <div className="w-1 h-4 rounded-full ml-2" style={{ background:"rgba(255,255,255,0.1)" }} />
        </div>
        <div className="flex items-center gap-2">
          <div className="w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background:"rgba(16,185,129,0.2)" }}>
            <MapPin size={11} style={{ color:"#34D399" }} />
          </div>
          <p className="text-sm text-white truncate">{post.destination}</p>
        </div>
      </div>

      <div className="flex items-center gap-3 text-xs mb-3" style={{ color:"rgba(255,255,255,0.45)" }}>
        <span className="flex items-center gap-1">
          <Weight size={11} /> {toPersianNum(post.weight_kg)} کیلوگرم
        </span>
        <span className="flex items-center gap-1">
          <Package size={11} /> {post.cargo_type}
        </span>
      </div>

      {isDriver && post.status === "open" && (
        <button
          onClick={() => onTake(post.id)}
          className="w-full py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all"
          style={{ background:"linear-gradient(135deg,#F97316,#FB923C)", boxShadow:"0 2px 10px rgba(249,115,22,0.4)" }}
        >
          پذیرفتن این بار
        </button>
      )}
    </div>
  );
}

// ── Empty state ───────────────────────────────────────────────
function EmptyState({ isDriver, onNew }: { isDriver: boolean; onNew: () => void }) {
  return (
    <div
      className="rounded-2xl p-8 text-center"
      style={{ background:"#1C1C1E", border:"1px dashed rgba(255,255,255,0.1)" }}
    >
      {isDriver ? (
        <>
          <Truck size={36} className="mx-auto mb-3" style={{ color:"rgba(255,255,255,0.2)" }} />
          <p className="text-sm font-semibold" style={{ color:"rgba(255,255,255,0.5)" }}>
            بار موجودی یافت نشد
          </p>
          <p className="text-xs mt-1" style={{ color:"rgba(255,255,255,0.3)" }}>
            بارهای جدید به‌زودی نمایش داده می‌شوند
          </p>
        </>
      ) : (
        <>
          <Package size={36} className="mx-auto mb-3" style={{ color:"rgba(255,255,255,0.2)" }} />
          <p className="text-sm font-semibold" style={{ color:"rgba(255,255,255,0.5)" }}>
            هنوز باری ثبت نکرده‌ای
          </p>
          <button
            onClick={onNew}
            className="mt-4 px-5 py-2.5 rounded-xl font-bold text-white text-sm active:scale-95"
            style={{ background:"linear-gradient(135deg,#06B6D4,#6366F1)" }}
          >
            ثبت اولین بار
          </button>
        </>
      )}
    </div>
  );
}
