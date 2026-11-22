import { Action, ActionPanel, List, Toast, showToast } from "@vicinae/api";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { basename, dirname } from "node:path";
import { useEffect, useState } from "react";

type Hit = { path: string; page: number | null; snippet: string };

function unearth(args: string[], signal: AbortSignal): Promise<Hit[]> {
  return new Promise((resolve, reject) =>
    execFile("unearth", ["search", ...args], { signal }, (error, stdout) => {
      if (error) {
        reject(error);
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch (parseError) {
        reject(parseError);
      }
    }),
  );
}

export default function Search() {
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<Hit[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed === "") {
      setHits([]);
      setIsLoading(false);
      return;
    }

    const controller = new AbortController();
    let ranked = false;
    setIsLoading(true);
    unearth(["--keyword-only", "--", trimmed], controller.signal).then(
      (keyword) => ranked || setHits(keyword),
      () => {},
    );
    unearth(["--", trimmed], controller.signal)
      .then((hybrid) => {
        ranked = true;
        setHits(hybrid);
      })
      .catch((error) => {
        if (!controller.signal.aborted) {
          showToast({ style: Toast.Style.Failure, title: "Semantic search failed", message: String(error) });
        }
      })
      .finally(() => controller.signal.aborted || setIsLoading(false));
    return () => controller.abort();
  }, [query]);

  const home = homedir();

  return (
    <List
      filtering={false}
      throttle
      isLoading={isLoading}
      onSearchTextChange={setQuery}
      searchBarPlaceholder="Search documents by meaning"
    >
      {hits.map((hit) => {
        const dir = dirname(hit.path);
        const displayDir =
          dir === home ? "~" : dir.startsWith(`${home}/`) ? `~${dir.slice(home.length)}` : dir;
        return (
          <List.Item
            key={hit.path}
            title={basename(hit.path)}
            subtitle={hit.snippet}
            icon={{ fileIcon: hit.path }}
            accessories={[
              ...(hit.page === null ? [] : [{ tag: `p. ${hit.page}` }]),
              { text: displayDir },
            ]}
          actions={
            <ActionPanel>
              <Action.Open title="Open" target={hit.path} />
              <Action.ShowInFinder path={hit.path} />
              <Action.CopyToClipboard title="Copy Path" content={hit.path} />
            </ActionPanel>
          }
        />
        );
      })}
    </List>
  );
}
