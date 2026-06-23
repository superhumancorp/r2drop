(() => {
  const appStoreUrl = "https://apps.apple.com/us/app/r2drop-cloudflare-r2-uploader/id6759578053?mt=12";
  const githubUrl = "https://github.com/superhumancorp/r2drop/releases";
  const scriptBase = document.currentScript ? new URL(".", document.currentScript.src).href : "";

  function platform() {
    if (navigator.userAgentData && navigator.userAgentData.platform) {
      return navigator.userAgentData.platform;
    }
    return navigator.platform || navigator.userAgent || "";
  }

  function isAppleDevice() {
    const value = platform();
    return /mac|iphone|ipad|ipod/i.test(value);
  }

  function relativeBadgePath() {
    if (scriptBase) {
      return new URL("app-store-badge.png", scriptBase).toString();
    }

    const path = window.location.pathname;
    return path.includes("/blog/") || path.includes("/privacy/") || path.includes("/terms/")
      ? "../app-store-badge.png"
      : "app-store-badge.png";
  }

  function setText(anchor, text) {
    const textNodes = anchor.querySelectorAll("[button-text], .button-arrow-text");
    if (textNodes.length > 0) {
      textNodes.forEach((node) => {
        node.textContent = text;
      });
      return;
    }

    const svg = anchor.querySelector("svg");
    if (svg && anchor.childNodes.length > 1) {
      anchor.childNodes.forEach((node) => {
        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
          node.textContent = text;
        }
      });
      return;
    }

    if (anchor.textContent.trim()) {
      anchor.textContent = text;
    }
  }

  function shouldUpdateLabel(anchor) {
    return anchor.hasAttribute("data-r2drop-download")
      || anchor.classList.contains("button-arrow")
      || anchor.classList.contains("btn-menu")
      || anchor.classList.contains("footer-link-item")
      || anchor.classList.contains("social-icon-link");
  }

  function renderBadge(anchor) {
    anchor.classList.add("app-store-badge-link");
    anchor.style.background = "transparent";
    anchor.style.borderRadius = "0";
    anchor.style.boxShadow = "none";
    anchor.style.padding = "0";
    anchor.style.display = "inline-flex";
    anchor.style.alignItems = "center";
    anchor.style.justifyContent = "center";
    anchor.innerHTML = "";

    const image = document.createElement("img");
    image.src = relativeBadgePath();
    image.alt = "Download on the App Store";
    image.className = "app-store-badge";
    image.loading = "lazy";
    image.style.display = "block";
    image.style.width = "auto";
    image.style.height = "44px";
    anchor.appendChild(image);
  }

  const useAppStore = isAppleDevice();
  const targetUrl = useAppStore ? appStoreUrl : githubUrl;
  const targetLabel = useAppStore ? "Download R2Drop on the Mac App Store" : "Download R2Drop from GitHub Releases";
  const targetText = useAppStore ? "Download on the App Store" : "Download for macOS";

  document.querySelectorAll(`a[href="${githubUrl}"], a[data-r2drop-download]`).forEach((anchor) => {
    anchor.href = targetUrl;
    anchor.target = "_blank";
    anchor.rel = "noopener";
    anchor.setAttribute("aria-label", targetLabel);

    if (useAppStore && anchor.hasAttribute("data-r2drop-app-store-badge")) {
      renderBadge(anchor);
    } else if (shouldUpdateLabel(anchor)) {
      setText(anchor, targetText);
    }
  });
})();
