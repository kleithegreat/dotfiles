// "AirDrop" in the page's context menu hands what was clicked to
// `desktopctl airdrop native-host`, which opens the shell's share card.

const HOST = "desktopctl.airdrop";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "airdrop",
      title: "AirDrop",
      contexts: ["selection", "link", "page"],
    });
  });
});

// selectionText collapses line breaks; the page's own selection keeps them.
async function selection(tab, frameId, fallback) {
  try {
    const target =
      frameId !== undefined ? { tabId: tab.id, frameIds: [frameId] } : { tabId: tab.id, allFrames: false };
    const [result] = await chrome.scripting.executeScript({
      target,
      func: () => getSelection().toString(),
    });
    return result?.result || fallback;
  } catch {
    return fallback;
  }
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  let message;
  if (info.selectionText) {
    const text = await selection(tab, info.frameId, info.selectionText);
    if (!text || !text.trim()) return;
    message = { text };
  } else {
    const url = info.linkUrl || info.pageUrl;
    if (!url) return;
    message = { url };
  }
  chrome.runtime.sendNativeMessage(HOST, message).catch(console.error);
});
