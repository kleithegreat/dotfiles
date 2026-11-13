// "AirDrop" in the page's context menu hands what was clicked to
// `desktopctl airdrop native-host`, which opens the shell's share card.

const HOST = "desktopctl.airdrop";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "airdrop",
    title: "AirDrop",
    contexts: ["selection", "link", "page"],
  });
});

// selectionText collapses line breaks; the page's own selection keeps them.
async function selection(tab, fallback) {
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id, allFrames: false },
      func: () => getSelection().toString(),
    });
    return result?.result || fallback;
  } catch {
    return fallback;
  }
}

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const message = info.selectionText
    ? { text: await selection(tab, info.selectionText) }
    : { url: info.linkUrl || info.pageUrl };
  chrome.runtime.sendNativeMessage(HOST, message);
});
