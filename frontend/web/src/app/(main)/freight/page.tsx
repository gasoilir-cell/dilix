"use client";

import { useState, useEffect } from "react";
import AppShell from "@/components/layout/AppShell";
import {
  Truck, Package, MapPin, Weight, Plus,
  Clock, CheckCircle2, AlertCircle, ChevronLeft,
  ArrowLeft, X, DollarSign, Calendar,
  Gavel, Star, Trophy, Loader2, Users,
  Navigation, PackageCheck, KeyRound, Route, Camera, ShieldCheck, Wallet,
  XCircle, RotateCcw,
} from "lucide-react";
import { useAuthStore } from "@/store/auth";
import { useTranslation } from "@/store/i18n";
import { toPersianNum, formatAmount } from "@/lib/utils";
import toast from "react-hot-toast";

// ── Types ─────────────────────────────────────────────────────
type CargoStatus =
  | "open" | "in_progress" | "picked_up" | "in_transit"
  | "delivered" | "received" | "cancelled";

interface CargoPost {
  id:          string;
  ref:         string;
  owner_id:    string;
  origin:      string;
  destination: string;
  cargo_type:  string;
  vehicle_type?: string | null;
  weight_kg:   number;
  price:       number;
  description: string | null;
  status:      CargoStatus;
  driver_id:   string | null;
  offers_count?: number;
  consignee_name?:  string | null;
  consignee_phone?: string | null;
  pod_photo_url?:   string | null;
  picked_up_at?:    string | null;
  delivered_at?:    string | null;
  received_at?:     string | null;
  last_lat?:        number | null;
  last_lng?:        number | null;
  last_location_at?: string | null;
  escrow_amount?:     number | null;
  escrow_status?:     string | null;
  commission_amount?: number | null;
  rated_by_me?:       boolean;
  pickup_code?:   string | null;
  delivery_code?: string | null;
  created_at:  string;
}

interface Offer {
  id:            string;
  driver_id:     string;
  driver_name:   string | null;
  driver_avatar: string | null;
  driver_rating: number;
  driver_trips:  number;
  price:         number;
  eta_days:      number | null;
  message:       string | null;
  status:        string;
  is_mine:       boolean;
  best:          boolean;
  created_at:    string;
}

interface TrackingEvent {
  id:         string;
  event_type: string;
  status:     string | null;
  lat:        number | null;
  lng:        number | null;
  note:       string | null;
  created_at: string;
}

interface VehicleType {
  code:          string;
  name_fa:       string;
  category:      string;
  max_weight_kg: number | null;
  icon:          string | null;
}

const STATUS: Record<CargoStatus, { label: string; color: string; icon: typeof Clock }> = {
  open:        { label: "frt.status.open",        color: "#F59E0B", icon: Clock },
  in_progress: { label: "frt.status.in_progress", color: "#6366F1", icon: Truck },
  picked_up:   { label: "frt.status.picked_up",   color: "#8B5CF6", icon: PackageCheck },
  in_transit:  { label: "frt.status.in_transit",  color: "#06B6D4", icon: Route },
  delivered:   { label: "frt.status.delivered",   color: "#14B8A6", icon: Navigation },
  received:    { label: "frt.status.received",    color: "#10B981", icon: CheckCircle2 },
  cancelled:   { label: "frt.status.cancelled",   color: "#F43F5E", icon: AlertCircle },
};

// مقدارِ value همان چیزی است که در بک‌اند ذخیره می‌شود (دست‌نخورده)؛ key فقط برای نمایش ترجمه می‌شود.
const CARGO_TYPES: { value: string; key: string }[] = [
  { value: "لوازم الکترونیک", key: "frt.cargo.electronics" },
  { value: "مواد غذایی",      key: "frt.cargo.food" },
  { value: "منسوجات",         key: "frt.cargo.textile" },
  { value: "مواد شیمیایی",    key: "frt.cargo.chemical" },
  { value: "ماشین‌آلات",      key: "frt.cargo.machinery" },
  { value: "پوشاک",           key: "frt.cargo.apparel" },
  { value: "مصالح ساختمانی",  key: "frt.cargo.construction" },
  { value: "سایر",            key: "frt.cargo.other" },
];

// value ذخیره‌شده در بک‌اند فارسی است؛ اگر در فهرست بود ترجمه، وگرنه خام نمایش داده می‌شود.
function cargoLabel(value: string, t: (k: string) => string): string {
  const found = CARGO_TYPES.find((c) => c.value === value);
  return found ? t(found.key) : value;
}

const API = process.env.NEXT_PUBLIC_API_URL ?? "https://dilix.ir/api/v1";

// ── Component ─────────────────────────────────────────────────
export default function FreightPage() {
  const { t } = useTranslation();
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
  const [vehicleTypes, setVehicleTypes] = useState<VehicleType[]>([]);

  // Form state
  const [form, setForm] = useState({
    origin: "", destination: "", cargo_type: "", vehicle_type: "", weight_kg: "",
    price: "", description: "", pickup_date: "", consignee_name: "", consignee_phone: "",
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

  const fetchVehicleTypes = async () => {
    try {
      const res = await fetch(`${API}/freight/vehicle-types`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error();
      setVehicleTypes(await res.json());
    } catch { /* ignore */ }
  };

  useEffect(() => {
    if (token) {
      fetchPosts(false);
      fetchVehicleTypes();
      if (!isDriver) fetchPosts(true);
    }
  }, [token]);

  // ── Submit new post ────────────────────────────────────────
  const submitPost = async () => {
    if (!form.origin || !form.destination || !form.cargo_type || !form.weight_kg || !form.price) {
      toast.error(t("frt.toast.fillRequired"));
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
          vehicle_type: form.vehicle_type || null,
          weight_kg:   parseFloat(form.weight_kg),
          price:       parseInt(form.price.replace(/,/g, "")),
          description: form.description || null,
          pickup_date: form.pickup_date || null,
          consignee_name:  form.consignee_name || null,
          consignee_phone: form.consignee_phone || null,
        }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.detail || t("frt.err"));
      }
      const newPost = await res.json();
      setMyPosts((prev) => [newPost, ...prev]);
      setForm({ origin:"", destination:"", cargo_type:"", vehicle_type:"", weight_kg:"", price:"", description:"", pickup_date:"", consignee_name:"", consignee_phone:"" });
      setShowForm(false);
      setActiveTab("mine");
      toast.success(t("frt.toast.postCreated"));
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.toast.postErr"));
    } finally {
      setSubmitting(false);
    }
  };

  // ── Refresh both lists ─────────────────────────────────────
  const refresh = () => {
    fetchPosts(false);
    if (!isDriver) fetchPosts(true);
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
      toast.success(t("frt.toast.taken"));
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.err"));
    }
  };

  // ── Styles ─────────────────────────────────────────────────
  const card = {
    background: "var(--surface-1)",
    border:     "1px solid var(--border-1)",
    borderRadius: "16px",
  };

  return (
    <AppShell title={t("frt.title")} showSearch={false}>
      <div className="px-4 pt-4 pb-6 space-y-4">

        {/* ── Tabs ── */}
        <div
          className="flex rounded-2xl p-1"
          style={{ background: "var(--surface-1)" }}
        >
          {isDriver ? (
            <TabBtn label={t("frt.tab.available")} icon={<Truck size={14}/>} active={activeTab==="list"} onClick={()=>setActiveTab("list")} />
          ) : (
            <>
              <TabBtn label={t("frt.tab.mine")} icon={<Package size={14}/>} active={activeTab==="mine"} onClick={()=>setActiveTab("mine")} />
              <TabBtn label={t("frt.tab.all")} icon={<Truck size={14}/>} active={activeTab==="list"} onClick={()=>setActiveTab("list")} />
            </>
          )}
        </div>

        {/* ── Stats (driver) ── */}
        {isDriver && (
          <div className="grid grid-cols-3 gap-3">
            {[
              { label:t("frt.stat.trips"),   value: toPersianNum(user?.total_trips ?? 0), color:"#F97316" },
              { label:t("frt.stat.available"),   value: toPersianNum(posts.length),            color:"#10B981" },
              { label:t("frt.stat.rating"),  value: user?.avg_rating ? toPersianNum((user.avg_rating/100).toFixed(1)) : "—", color:"#6366F1" },
            ].map((s) => (
              <div key={s.label} style={{ ...card, padding:"12px", textAlign:"center" }}>
                <p className="text-lg font-black text-white">{s.value}</p>
                <p className="text-[11px]" style={{ color:"var(--t-3)" }}>{s.label}</p>
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
            {t("frt.btn.newPost")}
          </button>
        )}

        {/* ── New post form ── */}
        {showForm && (
          <div style={{ ...card, padding:"20px" }} className="space-y-3">
            <div className="flex items-center justify-between mb-2">
              <h3 className="font-bold text-white">{t("frt.btn.newPost")}</h3>
              <button onClick={() => setShowForm(false)} style={{ color:"var(--t-3)" }}>
                <X size={20} />
              </button>
            </div>

            {[
              { key:"origin",      label:t("frt.f.origin"),      placeholder:t("frt.ph.origin") },
              { key:"destination", label:t("frt.f.destination"),      placeholder:t("frt.ph.destination") },
            ].map((f) => (
              <div key={f.key}>
                <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
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
              <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
                {t("frt.f.cargoType")} <span className="text-red-400">*</span>
              </label>
              <div className="flex gap-2 flex-wrap">
                {CARGO_TYPES.map((ct) => (
                  <button
                    key={ct.value}
                    onClick={() => setForm((p) => ({ ...p, cargo_type: ct.value }))}
                    className="text-xs px-3 py-1.5 rounded-full transition-all"
                    style={{
                      background: form.cargo_type===ct.value ? "rgba(99,102,241,0.3)" : "var(--surface-hover)",
                      border:     `1px solid ${form.cargo_type===ct.value ? "#6366F1" : "var(--border-1)"}`,
                      color:      form.cargo_type===ct.value ? "#818CF8" : "var(--t-2)",
                    }}
                  >
                    {t(ct.key)}
                  </button>
                ))}
              </div>
            </div>

            {/* نوع باربری (خودرو) */}
            {vehicleTypes.length > 0 && (
              <div>
                <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
                  {t("frt.f.vehicleType")}
                </label>
                <div className="flex gap-2 flex-wrap">
                  {vehicleTypes.map((v) => (
                    <button
                      key={v.code}
                      onClick={() => setForm((p) => ({ ...p, vehicle_type: p.vehicle_type === v.code ? "" : v.code }))}
                      className="text-xs px-3 py-1.5 rounded-full transition-all flex items-center gap-1"
                      style={{
                        background: form.vehicle_type===v.code ? "rgba(6,182,212,0.3)" : "var(--surface-hover)",
                        border:     `1px solid ${form.vehicle_type===v.code ? "#06B6D4" : "var(--border-1)"}`,
                        color:      form.vehicle_type===v.code ? "#67E8F9" : "var(--t-2)",
                      }}
                    >
                      <Truck size={11} /> {v.name_fa}
                    </button>
                  ))}
                </div>
              </div>
            )}

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
                  {t("frt.f.weight")} <span className="text-red-400">*</span>
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
                <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
                  {t("frt.f.price")} <span className="text-red-400">*</span>
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

            {/* گیرندهٔ نهایی */}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
                  {t("frt.f.consigneeName")}
                </label>
                <input
                  className="input w-full"
                  placeholder={t("frt.ph.consigneeName")}
                  value={form.consignee_name}
                  onChange={(e) => setForm((p) => ({ ...p, consignee_name: e.target.value }))}
                />
              </div>
              <div>
                <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
                  {t("frt.f.consigneePhone")}
                </label>
                <input
                  className="input w-full ltr text-left"
                  placeholder="0912..."
                  value={form.consignee_phone}
                  onChange={(e) => setForm((p) => ({ ...p, consignee_phone: e.target.value }))}
                />
              </div>
            </div>

            <div>
              <label className="text-xs font-medium mb-1 block" style={{ color:"var(--t-2)" }}>
                {t("frt.f.description")}
              </label>
              <textarea
                className="input w-full resize-none"
                rows={2}
                placeholder={t("frt.ph.description")}
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
              {submitting ? t("frt.btn.submitting") : t("frt.btn.submit")}
            </button>
          </div>
        )}

        {/* ── List of posts ── */}
        {loading ? (
          <div className="space-y-3">
            {[1,2,3].map((n) => (
              <div key={n} className="h-28 rounded-2xl animate-pulse" style={{ background:"var(--surface-1)" }} />
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
                  currentUserId={user?.id ?? ""}
                  token={token ?? ""}
                  vehicleTypes={vehicleTypes}
                  onTake={takePost}
                  onChanged={refresh}
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
        color:      active ? "#fff" : "var(--t-3)",
        boxShadow:  active ? "0 2px 8px rgba(99,102,241,0.4)" : "none",
      }}
    >
      {icon} {label}
    </button>
  );
}

// ── Post card ─────────────────────────────────────────────────
function PostCard({ post, isDriver, currentUserId, token, vehicleTypes, onTake, onChanged }: {
  post: CargoPost; isDriver: boolean; currentUserId: string; token: string;
  vehicleTypes: VehicleType[];
  onTake: (id: string) => void; onChanged: () => void;
}) {
  const { t } = useTranslation();
  const s = STATUS[post.status] ?? STATUS.open;
  const SIcon = s.icon;
  const isOwner = post.owner_id === currentUserId;
  const isMyDrive = post.driver_id === currentUserId;
  const vehicleName = vehicleTypes.find((v) => v.code === post.vehicle_type)?.name_fa;
  const isActive = ["in_progress", "picked_up", "in_transit", "delivered"].includes(post.status);

  // — bidding (driver) —
  const [showBid, setShowBid] = useState(false);
  const [bidPrice, setBidPrice] = useState("");
  const [bidEta, setBidEta] = useState("");
  const [bidMsg, setBidMsg] = useState("");
  const [bidding, setBidding] = useState(false);
  const [offered, setOffered] = useState(false);

  // — offers (owner) —
  const [showOffers, setShowOffers] = useState(false);
  const [offers, setOffers] = useState<Offer[] | null>(null);
  const [loadingOffers, setLoadingOffers] = useState(false);
  const [acceptingId, setAcceptingId] = useState<string | null>(null);

  const authHeaders = { "Content-Type": "application/json", Authorization: `Bearer ${token}` };

  const submitBid = async () => {
    const price = parseInt(bidPrice.replace(/,/g, ""));
    if (!price || price <= 0) { toast.error(t("frt.toast.bidPriceRequired")); return; }
    setBidding(true);
    try {
      const res = await fetch(`${API}/freight/posts/${post.id}/offers`, {
        method: "POST", headers: authHeaders,
        body: JSON.stringify({
          price,
          eta_days: bidEta ? parseInt(bidEta) : null,
          message: bidMsg || null,
        }),
      });
      if (!res.ok) { const e = await res.json(); throw new Error(e.detail || t("frt.err")); }
      setOffered(true);
      setShowBid(false);
      toast.success(t("frt.toast.bidPlaced"));
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.toast.bidErr"));
    } finally {
      setBidding(false);
    }
  };

  const loadOffers = async () => {
    const next = !showOffers;
    setShowOffers(next);
    if (next) {
      setLoadingOffers(true);
      try {
        const res = await fetch(`${API}/freight/posts/${post.id}/offers`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) throw new Error();
        setOffers(await res.json());
      } catch { setOffers([]); } finally { setLoadingOffers(false); }
    }
  };

  const acceptOffer = async (offerId: string) => {
    setAcceptingId(offerId);
    try {
      const res = await fetch(`${API}/freight/offers/${offerId}/accept`, {
        method: "POST", headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) { const e = await res.json(); throw new Error(e.detail || t("frt.err")); }
      toast.success(t("frt.toast.offerAccepted"));
      onChanged();
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.toast.acceptErr"));
    } finally {
      setAcceptingId(null);
    }
  };

  const [cancelling, setCancelling] = useState(false);
  const cancelPost = async () => {
    const withRefund = post.escrow_status === "locked";
    const ok = window.confirm(
      withRefund
        ? t("frt.confirm.cancelRefund")
        : t("frt.confirm.cancel"),
    );
    if (!ok) return;
    setCancelling(true);
    try {
      const res = await fetch(`${API}/freight/posts/${post.id}`, {
        method: "DELETE", headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok && res.status !== 204) { const e = await res.json().catch(() => ({})); throw new Error(e.detail || t("frt.err")); }
      toast.success(withRefund ? t("frt.toast.cancelledRefund") : t("frt.toast.cancelled"));
      onChanged();
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.toast.cancelErr"));
    } finally {
      setCancelling(false);
    }
  };

  return (
    <div
      className="rounded-2xl p-4"
      style={{ background:"var(--surface-1)", border:"1px solid var(--border-1)" }}
    >
      <div className="flex items-start justify-between mb-3">
        <div>
          <p className="text-xs font-mono" style={{ color:"var(--t-4)" }}>{post.ref}</p>
          <div className="flex items-center gap-1.5 mt-1">
            <SIcon size={13} style={{ color: s.color }} />
            <span className="text-xs font-semibold" style={{ color: s.color }}>{t(s.label)}</span>
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
          <div className="w-1 h-4 rounded-full ml-2" style={{ background:"var(--border-1)" }} />
        </div>
        <div className="flex items-center gap-2">
          <div className="w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background:"rgba(16,185,129,0.2)" }}>
            <MapPin size={11} style={{ color:"#34D399" }} />
          </div>
          <p className="text-sm text-white truncate">{post.destination}</p>
        </div>
      </div>

      <div className="flex items-center gap-3 text-xs mb-3 flex-wrap" style={{ color:"var(--t-3)" }}>
        <span className="flex items-center gap-1">
          <Weight size={11} /> {toPersianNum(post.weight_kg)} {t("frt.unit.kg")}
        </span>
        <span className="flex items-center gap-1">
          <Package size={11} /> {cargoLabel(post.cargo_type, t)}
        </span>
        {vehicleName && (
          <span className="flex items-center gap-1">
            <Truck size={11} /> {vehicleName}
          </span>
        )}
      </div>

      {/* ── راننده: پیشنهادِ قیمت روی بارِ open ── */}
      {isDriver && post.status === "open" && (
        <div className="space-y-2">
          {!showBid ? (
            <div className="flex gap-2">
              <button
                onClick={() => setShowBid(true)}
                disabled={offered}
                className="flex-1 py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all disabled:opacity-50 flex items-center justify-center gap-1.5"
                style={{ background:"linear-gradient(135deg,#6366F1,#8B5CF6)", boxShadow:"0 2px 10px rgba(99,102,241,0.4)" }}
              >
                <Gavel size={15} /> {offered ? t("frt.btn.offered") : t("frt.btn.bid")}
              </button>
              <button
                onClick={() => onTake(post.id)}
                className="flex-1 py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all"
                style={{ background:"linear-gradient(135deg,#F97316,#FB923C)", boxShadow:"0 2px 10px rgba(249,115,22,0.4)" }}
              >
                {t("frt.btn.takeCurrentPrice")}
              </button>
            </div>
          ) : (
            <div className="space-y-2 rounded-xl p-3" style={{ background:"var(--surface-2)" }}>
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold text-white">{t("frt.bid.yourOffer")}</p>
                <button onClick={() => setShowBid(false)} style={{ color:"var(--t-3)" }}><X size={16} /></button>
              </div>
              <input
                className="input w-full ltr text-left" type="number" placeholder={t("frt.ph.bidPrice")}
                value={bidPrice} onChange={(e) => setBidPrice(e.target.value)}
              />
              <input
                className="input w-full ltr text-left" type="number" placeholder={t("frt.ph.bidEta")}
                value={bidEta} onChange={(e) => setBidEta(e.target.value)}
              />
              <textarea
                className="input w-full resize-none" rows={2} placeholder={t("frt.ph.bidMsg")}
                value={bidMsg} onChange={(e) => setBidMsg(e.target.value)}
              />
              <button
                onClick={submitBid} disabled={bidding}
                className="w-full py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all disabled:opacity-60 flex items-center justify-center gap-1.5"
                style={{ background:"linear-gradient(135deg,#6366F1,#8B5CF6)" }}
              >
                {bidding ? <Loader2 size={15} className="animate-spin" /> : <><Gavel size={15} /> {t("frt.btn.submitBid")}</>}
              </button>
            </div>
          )}
        </div>
      )}

      {/* ── صاحبِ بار: مشاهدهٔ پیشنهادها روی بارِ open ── */}
      {isOwner && post.status === "open" && (
        <div className="space-y-2">
          <button
            onClick={loadOffers}
            className="w-full py-2.5 rounded-xl font-bold text-sm active:scale-95 transition-all flex items-center justify-center gap-1.5"
            style={{ background:"rgba(99,102,241,0.15)", border:"1px solid rgba(99,102,241,0.4)", color:"#A5B4FC" }}
          >
            <Users size={15} />
            {showOffers ? t("frt.btn.closeOffers") : `${t("frt.btn.offers")}${post.offers_count ? ` (${toPersianNum(post.offers_count)})` : ""}`}
          </button>

          {showOffers && (
            loadingOffers ? (
              <div className="flex justify-center py-3"><Loader2 size={18} className="animate-spin" style={{ color:"#818CF8" }} /></div>
            ) : !offers || offers.length === 0 ? (
              <p className="text-xs text-center py-3" style={{ color:"var(--t-4)" }}>{t("frt.offers.empty")}</p>
            ) : (
              <div className="space-y-2">
                {offers.map((o) => (
                  <div key={o.id} className="rounded-xl p-3"
                    style={{ background:"var(--surface-2)", border: o.best ? "1px solid rgba(16,185,129,0.5)" : "1px solid var(--border-soft)" }}>
                    <div className="flex items-center justify-between mb-1.5">
                      <div className="flex items-center gap-2 min-w-0">
                        <div className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0 overflow-hidden"
                          style={{ background:"rgba(99,102,241,0.2)" }}>
                          {o.driver_avatar
                            ? <img src={o.driver_avatar} alt="" className="w-full h-full object-cover" />
                            : <Truck size={13} style={{ color:"#818CF8" }} />}
                        </div>
                        <div className="min-w-0">
                          <p className="text-sm text-white truncate">{o.driver_name || t("frt.driverDefault")}</p>
                          <p className="text-[10px] flex items-center gap-1" style={{ color:"var(--t-3)" }}>
                            <Star size={9} style={{ color:"#FBBF24" }} /> {toPersianNum(o.driver_rating)} · {toPersianNum(o.driver_trips)} {t("frt.unit.trips")}
                          </p>
                        </div>
                      </div>
                      {o.best && (
                        <span className="text-[10px] px-2 py-0.5 rounded-full flex items-center gap-1 flex-shrink-0"
                          style={{ background:"rgba(16,185,129,0.2)", color:"#34D399" }}>
                          <Trophy size={10} /> {t("frt.best")}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center justify-between mt-1">
                      <div>
                        <p className="text-base font-black text-white">{formatAmount(o.price)}</p>
                        {o.eta_days != null && (
                          <p className="text-[10px]" style={{ color:"var(--t-3)" }}>{t("frt.etaPre")}{toPersianNum(o.eta_days)} {t("frt.unit.days")}</p>
                        )}
                      </div>
                      <button
                        onClick={() => acceptOffer(o.id)} disabled={acceptingId === o.id}
                        className="px-4 py-2 rounded-lg font-bold text-white text-xs active:scale-95 transition-all disabled:opacity-60 flex items-center gap-1.5"
                        style={{ background:"linear-gradient(135deg,#10B981,#34D399)" }}
                      >
                        {acceptingId === o.id ? <Loader2 size={13} className="animate-spin" /> : <><CheckCircle2 size={13} /> {t("frt.btn.accept")}</>}
                      </button>
                    </div>
                    {o.message && (
                      <p className="text-xs mt-2 pt-2" style={{ color:"var(--t-2)", borderTop:"1px solid var(--border-soft)" }}>
                        {o.message}
                      </p>
                    )}
                  </div>
                ))}
              </div>
            )
          )}

          <button
            onClick={cancelPost} disabled={cancelling}
            className="w-full py-2 rounded-xl font-semibold text-xs active:scale-95 transition-all disabled:opacity-60 flex items-center justify-center gap-1.5"
            style={{ background:"rgba(239,68,68,0.1)", border:"1px solid rgba(239,68,68,0.3)", color:"#F87171" }}
          >
            {cancelling ? <Loader2 size={13} className="animate-spin" /> : <XCircle size={13} />} {t("frt.btn.cancelPost")}
          </button>
        </div>
      )}

      {/* ── چرخهٔ عمرِ حمل (پس از تخصیص) ── */}
      {(isActive || post.status === "received") && (isOwner || isMyDrive) && (
        <LifecycleSection
          post={post}
          token={token}
          isOwner={isOwner}
          isMyDrive={isMyDrive}
          onChanged={onChanged}
        />
      )}
    </div>
  );
}

// ── Lifecycle (tracking + delivery flow) ──────────────────────
function LifecycleSection({ post, token, isOwner, isMyDrive, onChanged }: {
  post: CargoPost; token: string; isOwner: boolean; isMyDrive: boolean; onChanged: () => void;
}) {
  const { t } = useTranslation();
  const [busy, setBusy] = useState(false);
  const [pickupCode, setPickupCode] = useState("");
  const [deliveryCode, setDeliveryCode] = useState("");
  const [showTrack, setShowTrack] = useState(false);
  const [events, setEvents] = useState<TrackingEvent[] | null>(null);

  // — امتیازدهیِ متقابل (پس از تحویلِ نهایی) —
  const [ratingScore, setRatingScore] = useState(0);
  const [ratingHover, setRatingHover] = useState(0);
  const [ratingComment, setRatingComment] = useState("");
  const [ratingDone, setRatingDone] = useState(false);

  const jsonHeaders = { "Content-Type": "application/json", Authorization: `Bearer ${token}` };

  const call = async (path: string, body?: object) => {
    setBusy(true);
    try {
      const res = await fetch(`${API}/freight/posts/${post.id}/${path}`, {
        method: "POST", headers: jsonHeaders,
        body: body ? JSON.stringify(body) : undefined,
      });
      if (!res.ok) { const e = await res.json(); throw new Error(e.detail || t("frt.err")); }
      onChanged();
      return true;
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.err"));
      return false;
    } finally { setBusy(false); }
  };

  const doPickup = async () => {
    if (!pickupCode.trim()) { toast.error(t("frt.toast.pickupCodeRequired")); return; }
    if (await call("pickup", { code: pickupCode.trim() })) toast.success(t("frt.toast.pickupDone"));
  };

  const doDeliver = async () => {
    if (await call("deliver", {})) toast.success(t("frt.toast.deliverDone"));
  };

  const doReceive = async () => {
    if (!deliveryCode.trim()) { toast.error(t("frt.toast.deliveryCodeRequired")); return; }
    if (await call("receive", { code: deliveryCode.trim() })) toast.success(t("frt.toast.receiveDone"));
  };

  const doCancel = async () => {
    const withRefund = post.escrow_status === "locked";
    if (!window.confirm(
      withRefund
        ? t("frt.confirm.cancelRefundPre")
        : t("frt.confirm.cancel"),
    )) return;
    setBusy(true);
    try {
      const res = await fetch(`${API}/freight/posts/${post.id}`, {
        method: "DELETE", headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok && res.status !== 204) { const e = await res.json().catch(() => ({})); throw new Error(e.detail || t("frt.err")); }
      toast.success(withRefund ? t("frt.toast.cancelledRefund") : t("frt.toast.cancelled"));
      onChanged();
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.toast.cancelErr"));
    } finally { setBusy(false); }
  };

  const sendLocation = () => {
    if (!navigator.geolocation) { toast.error(t("frt.toast.geoUnavailable")); return; }
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const ok = await call("location", { lat: pos.coords.latitude, lng: pos.coords.longitude });
        if (ok) toast.success(t("frt.toast.locationSaved"));
      },
      () => { setBusy(false); toast.error(t("frt.toast.geoDenied")); },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  };

  const submitRating = async () => {
    if (ratingScore < 1) { toast.error(t("frt.toast.selectStar")); return; }
    setBusy(true);
    try {
      const res = await fetch(`${API}/freight/posts/${post.id}/rate`, {
        method: "POST", headers: jsonHeaders,
        body: JSON.stringify({ score: ratingScore, comment: ratingComment || null }),
      });
      if (!res.ok) { const e = await res.json(); throw new Error(e.detail || t("frt.err")); }
      setRatingDone(true);
      toast.success(t("frt.toast.rated"));
    } catch (e: unknown) {
      toast.error((e as Error).message || t("frt.toast.rateErr"));
    } finally { setBusy(false); }
  };

  const loadTracking = async () => {
    const next = !showTrack;
    setShowTrack(next);
    if (next && events === null) {
      try {
        const res = await fetch(`${API}/freight/posts/${post.id}/tracking`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) throw new Error();
        setEvents(await res.json());
      } catch { setEvents([]); }
    }
  };

  const escrowAmt = post.escrow_amount ?? 0;
  const commission = post.commission_amount ?? Math.floor(escrowAmt * 0.1);
  const netPayout = escrowAmt - commission;

  return (
    <div className="mt-3 pt-3 space-y-2" style={{ borderTop:"1px solid var(--border-1)" }}>

      {/* وضعیتِ امانی (escrow) */}
      {post.escrow_status === "locked" && escrowAmt > 0 && (
        <div className="rounded-xl p-3 flex items-center gap-2" style={{ background:"rgba(6,182,212,0.1)", border:"1px solid rgba(6,182,212,0.25)" }}>
          <Wallet size={16} style={{ color:"#22D3EE" }} />
          {isOwner ? (
            <p className="text-xs text-white">{t("frt.escrow.lockedOwnerPre")}<span className="font-black">{formatAmount(escrowAmt)}</span>{t("frt.escrow.lockedOwnerSuf")}</p>
          ) : (
            <p className="text-xs text-white">{t("frt.escrow.driverIncomePre")}<span className="font-black">{formatAmount(netPayout)}</span> <span style={{ color:"var(--t-3)" }}>{t("frt.escrow.commissionPre")}{toPersianNum(10)}{t("frt.escrow.commissionSuf")}</span></p>
          )}
        </div>
      )}
      {post.escrow_status === "released" && (
        <div className="rounded-xl p-3 flex items-center gap-2" style={{ background:"rgba(16,185,129,0.1)", border:"1px solid rgba(16,185,129,0.25)" }}>
          <ShieldCheck size={16} style={{ color:"#34D399" }} />
          <p className="text-xs text-white">
            {isOwner
              ? <>{t("frt.escrow.settledOwnerPre")}<span className="font-black">{formatAmount(netPayout)}</span>{t("frt.escrow.settledOwnerSuf")}</>
              : <>{t("frt.escrow.settledDriverPre")}<span className="font-black">{formatAmount(netPayout)}</span>{t("frt.escrow.settledDriverSuf")}</>}
          </p>
        </div>
      )}
      {post.escrow_status === "refunded" && (
        <div className="rounded-xl p-3 flex items-center gap-2" style={{ background:"rgba(148,163,184,0.1)", border:"1px solid rgba(148,163,184,0.25)" }}>
          <RotateCcw size={16} style={{ color:"#94A3B8" }} />
          <p className="text-xs text-white">
            {isOwner
              ? <>{t("frt.escrow.refundedOwnerPre")}<span className="font-black">{formatAmount(escrowAmt)}</span>{t("frt.escrow.refundedOwnerSuf")}</>
              : <>{t("frt.escrow.refundedDriver")}</>}
          </p>
        </div>
      )}

      {/* کدهای تأیید برای صاحبِ بار */}
      {isOwner && post.pickup_code && post.status === "in_progress" && (
        <div className="rounded-xl p-3 flex items-center gap-2" style={{ background:"rgba(139,92,246,0.12)", border:"1px solid rgba(139,92,246,0.3)" }}>
          <KeyRound size={16} style={{ color:"#A78BFA" }} />
          <p className="text-xs text-white">{t("frt.code.pickupToDriver")}<span className="font-black text-base ltr">{toPersianNum(post.pickup_code)}</span></p>
        </div>
      )}

      {/* صاحبِ بار — لغو و بازگشتِ وجه (پیش از تحویل‌گیریِ راننده) */}
      {isOwner && post.status === "in_progress" && (
        <button onClick={doCancel} disabled={busy}
          className="w-full py-2 rounded-xl font-semibold text-xs active:scale-95 transition-all disabled:opacity-60 flex items-center justify-center gap-1.5"
          style={{ background:"rgba(239,68,68,0.1)", border:"1px solid rgba(239,68,68,0.3)", color:"#F87171" }}>
          {busy ? <Loader2 size={13} className="animate-spin" /> : <XCircle size={13} />}
          {post.escrow_status === "locked" ? t("frt.btn.cancelRefund") : t("frt.btn.cancelPost")}
        </button>
      )}
      {isOwner && post.delivery_code && post.status === "delivered" && (
        <div className="rounded-xl p-3 flex items-center gap-2" style={{ background:"rgba(20,184,166,0.12)", border:"1px solid rgba(20,184,166,0.3)" }}>
          <KeyRound size={16} style={{ color:"#2DD4BF" }} />
          <p className="text-xs text-white">{t("frt.code.consignee")}<span className="font-black text-base ltr">{toPersianNum(post.delivery_code)}</span></p>
        </div>
      )}

      {/* راننده — تحویل‌گیری در مبدأ */}
      {isMyDrive && post.status === "in_progress" && (
        <div className="flex gap-2">
          <input
            className="input flex-1 ltr text-center" inputMode="numeric" placeholder={t("frt.ph.pickupCode")}
            value={pickupCode} onChange={(e) => setPickupCode(e.target.value)}
          />
          <button onClick={doPickup} disabled={busy}
            className="px-4 py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all disabled:opacity-60 flex items-center gap-1.5"
            style={{ background:"linear-gradient(135deg,#8B5CF6,#A78BFA)" }}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <PackageCheck size={15} />} {t("frt.btn.pickup")}
          </button>
        </div>
      )}

      {/* راننده — در مسیر: ثبت موقعیت + تحویل در مقصد */}
      {isMyDrive && (post.status === "picked_up" || post.status === "in_transit") && (
        <div className="flex gap-2">
          <button onClick={sendLocation} disabled={busy}
            className="flex-1 py-2.5 rounded-xl font-bold text-sm active:scale-95 transition-all disabled:opacity-60 flex items-center justify-center gap-1.5"
            style={{ background:"rgba(6,182,212,0.15)", border:"1px solid rgba(6,182,212,0.4)", color:"#67E8F9" }}>
            <Navigation size={15} /> {t("frt.btn.sendLocation")}
          </button>
          <button onClick={doDeliver} disabled={busy}
            className="flex-1 py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all disabled:opacity-60 flex items-center justify-center gap-1.5"
            style={{ background:"linear-gradient(135deg,#14B8A6,#2DD4BF)" }}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <PackageCheck size={15} />} {t("frt.btn.deliver")}
          </button>
        </div>
      )}

      {/* صاحبِ بار — تأیید دریافتِ نهایی */}
      {isOwner && post.status === "delivered" && (
        <div className="flex gap-2">
          <input
            className="input flex-1 ltr text-center" inputMode="numeric" placeholder={t("frt.ph.deliveryCode")}
            value={deliveryCode} onChange={(e) => setDeliveryCode(e.target.value)}
          />
          <button onClick={doReceive} disabled={busy}
            className="px-4 py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all disabled:opacity-60 flex items-center gap-1.5"
            style={{ background:"linear-gradient(135deg,#10B981,#34D399)" }}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <ShieldCheck size={15} />} {t("frt.btn.confirmReceive")}
          </button>
        </div>
      )}

      {/* امتیازدهیِ متقابل — پس از تحویلِ نهایی */}
      {post.status === "received" && (isOwner || isMyDrive) && (
        ratingDone || post.rated_by_me ? (
          <div className="rounded-xl p-3 flex items-center gap-2" style={{ background:"rgba(251,191,36,0.1)", border:"1px solid rgba(251,191,36,0.25)" }}>
            <Star size={16} style={{ color:"#FBBF24", fill:"#FBBF24" }} />
            <p className="text-xs text-white">{t("frt.rating.done")}</p>
          </div>
        ) : (
          <div className="rounded-xl p-3 space-y-2" style={{ background:"var(--surface-2)", border:"1px solid rgba(251,191,36,0.25)" }}>
            <p className="text-xs font-semibold text-white">
              {isOwner ? t("frt.rating.rateDriver") : t("frt.rating.rateOwner")}
            </p>
            <div className="flex items-center gap-1.5" dir="ltr">
              {[1,2,3,4,5].map((n) => (
                <button
                  key={n}
                  onClick={() => setRatingScore(n)}
                  onMouseEnter={() => setRatingHover(n)}
                  onMouseLeave={() => setRatingHover(0)}
                  className="active:scale-90 transition-transform"
                >
                  <Star size={26}
                    style={{ color:"#FBBF24", fill: (ratingHover || ratingScore) >= n ? "#FBBF24" : "transparent" }} />
                </button>
              ))}
            </div>
            <textarea
              className="input w-full resize-none" rows={2} placeholder={t("frt.ph.ratingComment")}
              value={ratingComment} onChange={(e) => setRatingComment(e.target.value)}
            />
            <button onClick={submitRating} disabled={busy}
              className="w-full py-2.5 rounded-xl font-bold text-white text-sm active:scale-95 transition-all disabled:opacity-60 flex items-center justify-center gap-1.5"
              style={{ background:"linear-gradient(135deg,#F59E0B,#FBBF24)" }}>
              {busy ? <Loader2 size={14} className="animate-spin" /> : <Star size={15} />} {t("frt.btn.submitRating")}
            </button>
          </div>
        )
      )}

      {/* دکمهٔ رهگیری */}
      <button onClick={loadTracking}
        className="w-full py-2 rounded-xl font-semibold text-xs active:scale-95 transition-all flex items-center justify-center gap-1.5"
        style={{ background:"var(--surface-2)", color:"var(--t-2)" }}>
        <Route size={13} /> {showTrack ? t("frt.btn.closeTracking") : t("frt.btn.tracking")}
      </button>

      {showTrack && (
        events === null ? (
          <div className="flex justify-center py-2"><Loader2 size={16} className="animate-spin" style={{ color:"#818CF8" }} /></div>
        ) : events.length === 0 ? (
          <p className="text-xs text-center py-2" style={{ color:"var(--t-4)" }}>{t("frt.tracking.empty")}</p>
        ) : (
          <div className="space-y-2 pr-1">
            {events.map((ev) => (
              <div key={ev.id} className="flex items-start gap-2">
                <div className="w-2 h-2 rounded-full mt-1.5 flex-shrink-0" style={{ background: STATUS[(ev.status as CargoStatus)]?.color ?? "#6366F1" }} />
                <div className="min-w-0">
                  <p className="text-xs text-white">{TRACK_LABEL[ev.event_type] ? t(TRACK_LABEL[ev.event_type]) : ev.event_type}</p>
                  {ev.note && <p className="text-[10px]" style={{ color:"var(--t-3)" }}>{ev.note}</p>}
                  <p className="text-[10px]" style={{ color:"var(--t-4)" }}>
                    {new Date(ev.created_at).toLocaleString("fa-IR", { dateStyle:"short", timeStyle:"short" })}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )
      )}
    </div>
  );
}

const TRACK_LABEL: Record<string, string> = {
  created:   "frt.track.created",
  accepted:  "frt.track.accepted",
  picked_up: "frt.track.picked_up",
  location:  "frt.track.location",
  delivered: "frt.track.delivered",
  received:  "frt.track.received",
  cancelled: "frt.track.cancelled",
};

// ── Empty state ───────────────────────────────────────────────
function EmptyState({ isDriver, onNew }: { isDriver: boolean; onNew: () => void }) {
  const { t } = useTranslation();
  return (
    <div
      className="rounded-2xl p-8 text-center"
      style={{ background:"var(--surface-1)", border:"1px dashed var(--border-1)" }}
    >
      {isDriver ? (
        <>
          <Truck size={36} className="mx-auto mb-3" style={{ color:"var(--t-5)" }} />
          <p className="text-sm font-semibold" style={{ color:"var(--t-3)" }}>
            {t("frt.empty.driverTitle")}
          </p>
          <p className="text-xs mt-1" style={{ color:"var(--t-4)" }}>
            {t("frt.empty.driverSub")}
          </p>
        </>
      ) : (
        <>
          <Package size={36} className="mx-auto mb-3" style={{ color:"var(--t-5)" }} />
          <p className="text-sm font-semibold" style={{ color:"var(--t-3)" }}>
            {t("frt.empty.ownerTitle")}
          </p>
          <button
            onClick={onNew}
            className="mt-4 px-5 py-2.5 rounded-xl font-bold text-white text-sm active:scale-95"
            style={{ background:"linear-gradient(135deg,#06B6D4,#6366F1)" }}
          >
            {t("frt.empty.ownerBtn")}
          </button>
        </>
      )}
    </div>
  );
}
