const form = document.querySelector("#search-form");
const input = document.querySelector("#search-input");
const message = document.querySelector("#message");
const siteStatus = document.querySelector("#site-status");
const results = document.querySelector("#results");

const availabilityLabels = {
  in_stock: "在庫あり",
  low_stock: "残りわずか",
  out_of_stock: "在庫なし",
};

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const query = input.value.trim();
  if (!query) {
    showMessage("検索キーワードを入力してください。", "error");
    return;
  }

  setLoading(true);
  clearResults();
  showMessage("検索中です。", "success");

  try {
    const response = await fetch(`/api/books?q=${encodeURIComponent(query)}`);
    const payload = await response.json();

    if (!response.ok) {
      throw new Error(payload.message || "検索に失敗しました。");
    }

    renderSiteStatus(payload.sites || []);
    renderResults(payload.results || []);

    const resultCount = payload.results?.length || 0;
    showMessage(
      `${resultCount}件の結果を取得しました。処理時間: ${payload.elapsed_ms}ms`,
      "success",
    );
  } catch (error) {
    showMessage(error.message || "検索に失敗しました。", "error");
  } finally {
    setLoading(false);
  }
});

function setLoading(isLoading) {
  const button = form.querySelector("button");
  button.disabled = isLoading;
  button.textContent = isLoading ? "検索中..." : "検索";
}

function clearResults() {
  results.innerHTML = "";
  siteStatus.innerHTML = "";
  siteStatus.className = "site-status";
}

function showMessage(text, type) {
  message.textContent = text;
  message.className = `message is-visible ${type}`;
}

function renderSiteStatus(sites) {
  if (sites.length === 0) {
    return;
  }

  const items = sites
    .map((site) => {
      const statusText =
        site.status === "success"
          ? `成功: ${site.result_count}件`
          : `失敗: ${site.error || "unknown error"}`;
      return `<li>${escapeHtml(site.site_name)} - ${escapeHtml(statusText)}</li>`;
    })
    .join("");

  siteStatus.innerHTML = `<ul>${items}</ul>`;
  siteStatus.className = "site-status is-visible";
}

function renderResults(books) {
  if (books.length === 0) {
    results.innerHTML = "";
    return;
  }

  results.innerHTML = books.map(renderBookCard).join("");
}

function renderBookCard(book) {
  const price = new Intl.NumberFormat("ja-JP", {
    style: "currency",
    currency: book.currency || "JPY",
  }).format(book.price);

  return `
    <article class="book-card">
      <h2>${escapeHtml(book.title)}</h2>
      <p class="book-meta">${escapeHtml(book.author)}</p>
      <div class="book-detail">
        <div><span>価格</span><strong>${escapeHtml(price)}</strong></div>
        <div><span>在庫</span><strong>${escapeHtml(availabilityLabels[book.availability] || book.availability)}</strong></div>
        <div><span>サイト</span><strong>${escapeHtml(book.site_name)}</strong></div>
      </div>
      <a href="${escapeAttribute(book.url)}" target="_blank" rel="noreferrer">商品ページを見る</a>
    </article>
  `;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttribute(value) {
  return escapeHtml(value).replaceAll("`", "&#096;");
}
