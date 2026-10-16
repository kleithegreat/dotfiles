import { Action, ActionPanel, List, Toast, showToast } from "@vicinae/api";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { basename, dirname } from "node:path";
import { useEffect, useState } from "react";

type Hit = { path: string; page: number | null; snippet: string };

function unearth(args: string[], signal: AbortSignal): Promise<Hit[]> {
  return new Promise((resolve, reject) =>
    execFile("unearth", ["search", ...args], { signal }, (error, stdout) =>
      error ? reject(error) : resolve(JSON.parse(stdout)),
    ),
  );
}

export default function Search() {
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<Hit[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    const controller = new AbortController();
    let ranked = false;
    setIsLoading(query.trim() !== "");
    unearth(["--keyword-only", "--", query], controller.signal).then(
      (keyword) => ranked || setHits(keyword),
      () => {},
    );
    unearth(["--", query], controller.signal)
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

  return (
    <List
      filtering={false}
      throttle
      isLoading={isLoading}
      onSearchTextChange={setQuery}
      searchBarPlaceholder="Search documents by meaning"
    >
      {hits.map((hit) => (
        <List.Item
          key={hit.path}
          title={basename(hit.path)}
          subtitle={hit.snippet}
          icon={{ fileIcon: hit.path }}
          accessories={[
            hit.page === null ? {} : { tag: `p. ${hit.page}` },
            { text: dirname(hit.path).replace(homedir(), "~") },
          ]}
          actions={
            <ActionPanel>
              <Action.Open title="Open" target={hit.path} />
              <Action.ShowInFinder path={hit.path} />
              <Action.CopyToClipboard title="Copy Path" content={hit.path} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
