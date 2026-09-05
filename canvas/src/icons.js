import AiBrain01Icon from "@hugeicons/core-free-icons/AiBrain01Icon";
import Analytics01Icon from "@hugeicons/core-free-icons/Analytics01Icon";
import BrowserIcon from "@hugeicons/core-free-icons/BrowserIcon";
import Calendar01Icon from "@hugeicons/core-free-icons/Calendar01Icon";
import CodeIcon from "@hugeicons/core-free-icons/CodeIcon";
import CreditCardIcon from "@hugeicons/core-free-icons/CreditCardIcon";
import Database01Icon from "@hugeicons/core-free-icons/Database01Icon";
import FolderFileStorageIcon from "@hugeicons/core-free-icons/FolderFileStorageIcon";
import Notification01Icon from "@hugeicons/core-free-icons/Notification01Icon";
import QrCodeScanIcon from "@hugeicons/core-free-icons/QrCodeScanIcon";
import SecurityCheckIcon from "@hugeicons/core-free-icons/SecurityCheckIcon";
import Wifi01Icon from "@hugeicons/core-free-icons/Wifi01Icon";

const brandIcons = {
  supabase: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/supabase/default.svg",
  stripe: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/stripe/default.svg",
  livekit: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/livekit/default.svg",
  openai: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/openai/default.svg",
};

function iconFor(component) {
  if (component.type === "frontend") return BrowserIcon;
  if (component.type === "agent") return AiBrain01Icon;
  if (component.type === "analytics") return Analytics01Icon;
  if (component.type === "database") return Database01Icon;
  if (component.type === "storage") return FolderFileStorageIcon;
  if (component.type === "identity") return SecurityCheckIcon;

  const identity = `${component.id} ${component.name} ${component.technology ?? ""}`.toLowerCase();
  if (identity.includes("stripe") || identity.includes("billing") || identity.includes("invoice")) return CreditCardIcon;
  if (identity.includes("calendar") || identity.includes("appointment") || identity.includes("booking")) return Calendar01Icon;
  if (identity.includes("qr") || identity.includes("check-in") || identity.includes("attendance")) return QrCodeScanIcon;
  if (identity.includes("email") || identity.includes("notification") || identity.includes("reminder")) return Notification01Icon;
  if (identity.includes("realtime") || identity.includes("real-time") || identity.includes("availability")) return Wifi01Icon;
  return CodeIcon;
}

function escapeAttribute(value) {
  return String(value).replaceAll("&", "&amp;").replaceAll('"', "&quot;");
}

function kebabCase(attribute) {
  return attribute.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
}

function asSvg(icon, color) {
  const shapes = icon
    .map(([tag, attributes]) => {
      const props = Object.entries(attributes)
        .filter(([key]) => key !== "key")
        .map(([key, value]) => `${kebabCase(key)}="${escapeAttribute(value === "currentColor" ? color : value)}"`)
        .join(" ");
      return `<${tag} ${props}/>`;
    })
    .join("");
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">${shapes}</svg>`;
}

export function iconFileId(component) {
  return `icon-${component.id}`;
}

export function iconDataUrl(component, color = "#312e81") {
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(asSvg(iconFor(component), color))}`;
}

export function brandIconUrl(component) {
  const identity = `${component.name} ${component.technology ?? ""}`.toLowerCase();
  return Object.entries(brandIcons).find(([brand]) => identity.includes(brand))?.[1] ?? null;
}
