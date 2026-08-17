import { createRoot } from "react-dom/client";
import App from "./App";
import "./index.css";

// The frontend gate placeholder that used to live here is gone: evidence/ui-study.md now exists
// with 70 verified path:line citations (audited by scripts/74-verify-ui-study.sh), so the gate is
// open and every component names the pattern it applies.
const root = document.getElementById("root");
if (root) {
  createRoot(root).render(<App />);
}
