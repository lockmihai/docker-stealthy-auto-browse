/**
 * get_elements.js
 *
 * Extracts all interactive elements from the current page.
 * Injected via Playwright's page.evaluate().
 *
 * Returns an array of element objects with selectors and positions,
 * suitable for automated clicking/interaction.
 *
 * @param {boolean} visibleOnly - If true, only return elements in viewport
 * @returns {Array<Object>} Array of element descriptors
 */
(visibleOnly) => {
  // All CSS selectors for interactive elements we care about
  // These cover: links, buttons, form inputs, ARIA roles, click handlers, etc.
  const SELECTORS = [
    "a[href]", // Links
    "button", // Buttons
    "input", // Input fields
    "select", // Dropdowns
    "textarea", // Text areas
    '[role="button"]', // ARIA buttons
    '[role="link"]', // ARIA links
    '[role="checkbox"]', // ARIA checkboxes
    '[role="radio"]', // ARIA radio buttons
    '[role="tab"]', // ARIA tabs
    '[role="menuitem"]', // ARIA menu items
    "[onclick]", // Elements with onclick handlers
    '[tabindex]:not([tabindex="-1"])', // Focusable elements (not disabled)
    "label[for]", // Labels that activate inputs
    "summary", // Collapsible summary elements
    '[contenteditable="true"]', // Editable content areas
  ].join(",");

  /**
   * Generate a unique CSS selector or XPath for an element.
   * Tries multiple strategies in order of reliability:
   * 1. ID (most reliable)
   * 2. Unique class
   * 3. Name attribute
   * 4. Common attributes (data-testid, aria-label, etc.)
   * 5. XPath fallback (always works but brittle)
   */
  const getSelector = (el) => {
    // Strategy 1: ID selector - most reliable
    if (el.id) return "#" + el.id;

    // Strategy 2: Try first class if it's unique on the page
    if (el.className && typeof el.className === "string") {
      const cls = el.className
        .trim()
        .split(/\s+/)
        .filter((c) => c)[0];
      if (cls) {
        const sel = el.tagName.toLowerCase() + "." + cls;
        try {
          // Only use if this selector matches exactly one element
          if (document.querySelectorAll(sel).length === 1) return sel;
        } catch (e) {
          // Invalid selector (class has special chars), skip
        }
      }
    }

    // Strategy 3: Name attribute (common for form fields)
    if (el.name) return el.tagName.toLowerCase() + '[name="' + el.name + '"]';

    // Strategy 4: Try common identifying attributes
    for (const attr of ["data-testid", "aria-label", "title", "placeholder"]) {
      const val = el.getAttribute(attr);
      if (val)
        return (
          el.tagName.toLowerCase() +
          "[" +
          attr +
          '="' +
          val.replace(/"/g, '\\"') +
          '"]'
        );
    }

    // Strategy 5: XPath fallback - walks up the DOM tree
    // Builds path like /html[1]/body[1]/div[2]/button[1]
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1) {
      // Count same-tag siblings before this node to get index
      let idx = 1,
        sib = node.previousSibling;
      while (sib) {
        if (sib.nodeType === 1 && sib.tagName === node.tagName) idx++;
        sib = sib.previousSibling;
      }
      parts.unshift(node.tagName.toLowerCase() + "[" + idx + "]");
      node = node.parentNode;
    }
    return "/" + parts.join("/");
  };

  const results = [];
  let idx = 0;

  // Query all interactive elements and filter/collect
  document.querySelectorAll(SELECTORS).forEach((el) => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);

    // Skip elements with no dimensions (collapsed, display:none, etc.)
    if (rect.width === 0 || rect.height === 0) return;

    // Skip hidden elements
    if (
      style.visibility === "hidden" ||
      style.display === "none" ||
      style.opacity === "0"
    )
      return;

    // Check if element is within the visible viewport
    const inViewport =
      rect.top < window.innerHeight &&
      rect.bottom > 0 &&
      rect.left < window.innerWidth &&
      rect.right > 0;

    // If visibleOnly mode, skip elements outside viewport
    if (visibleOnly && !inViewport) return;

    // Build element descriptor object
    results.push({
      i: idx, // Index for easy reference
      tag: el.tagName.toLowerCase(), // HTML tag name
      id: el.id || null, // ID if present
      // Human-readable text content
      text: (
        el.innerText || // Text inside element
        el.value || // Input value
        el.placeholder || // Placeholder text
        el.alt || // Alt text (images)
        el.getAttribute("aria-label") || // ARIA label
        ""
      )
        .trim()
        .replace(/\s+/g, " ")
        .substring(0, 60), // Clean up whitespace, limit length
      selector: getSelector(el), // CSS selector or XPath to target this element
      x: Math.round(rect.left + rect.width / 2), // Center X coordinate
      y: Math.round(rect.top + rect.height / 2), // Center Y coordinate
      w: Math.round(rect.width), // Width
      h: Math.round(rect.height), // Height
      visible: inViewport, // Whether in viewport
    });
    idx++;
  });

  return results;
};
