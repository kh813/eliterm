let Hooks = {};

Hooks.Terminal = {
  mounted() {
    let colors = JSON.parse(this.el.dataset.colors || "{}");
    const defaultFont = 'Consolas, "Cascadia Code", Menlo, Monaco, "Courier New", monospace';
    const userFont = this.el.dataset.font;
    const finalFont = userFont ? `"${userFont}", ${defaultFont}` : defaultFont;

    this.term = new window.Terminal({
      cursorBlink: true,
      fontFamily: finalFont,
      fontSize: 14,
      allowTransparency: false,
      theme: Object.assign({
        background: '#000000',
        foreground: '#e5e5e5',
        cursor: '#4ade80',
        selectionBackground: 'rgba(255, 255, 255, 0.3)'
      }, colors),
      macOptionClickForcesSelection: true,
      macOptionIsMeta: true
    });
    
    if (colors.background) {
      this.el.parentElement.style.backgroundColor = colors.background;
      this.el.parentElement.parentElement.style.backgroundColor = colors.background;
    } else {
      this.el.parentElement.style.backgroundColor = '#000000';
      this.el.parentElement.parentElement.style.backgroundColor = '#000000';
    }

    this.fitAddon = new window.FitAddon.FitAddon();
    this.term.loadAddon(this.fitAddon);

    this.term.open(this.el);
    this.fitAddon.fit();
    
    // Ensure correct alignment after fonts load
    if (document.fonts) {
      document.fonts.ready.then(() => {
        this.fitAddon.fit();
        this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
      });
    }

    // Handle terminal input
    this.term.onData(data => {
      this.pushEvent("terminal_input", { data: data });
    });

    // Handle incoming data from Elixir
    this.handleEvent("terminal_output", payload => {
      // Decode Base64 to Uint8Array
      const binaryString = atob(payload.data);
      const len = binaryString.length;
      const bytes = new Uint8Array(len);
      for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }
      this.term.write(bytes);
    });

    // Handle incoming theme updates
    this.handleEvent("terminal_theme", payload => {
      let colors = payload.colors;
      this.term.options.theme = Object.assign({
        background: '#000000',
        foreground: '#e5e5e5',
        cursor: '#4ade80',
        selectionBackground: 'rgba(255, 255, 255, 0.3)'
      }, colors);
      
      if (colors.background) {
        this.el.parentElement.style.backgroundColor = colors.background;
        this.el.parentElement.parentElement.style.backgroundColor = colors.background;
      } else {
        this.el.parentElement.style.backgroundColor = '#000000';
        this.el.parentElement.parentElement.style.backgroundColor = '#000000';
      }
    });

    // Handle incoming font updates
    this.handleEvent("terminal_font", payload => {
      const defaultFont = 'Consolas, "Cascadia Code", Menlo, Monaco, "Courier New", monospace';
      const userFont = payload.font;
      const finalFont = userFont ? `"${userFont}", ${defaultFont}` : defaultFont;
      this.term.options.fontFamily = finalFont;
      
      // Ensure correct alignment after fonts load
      if (document.fonts) {
        document.fonts.ready.then(() => {
          this.fitAddon.fit();
          this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
        });
      } else {
        this.fitAddon.fit();
        this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
      }
    });

    // Resize handling using ResizeObserver (robust for dynamically sized containers)
    const resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit();
      this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
    });
    resizeObserver.observe(this.el);

    // Initial resize
    setTimeout(() => {
      this.fitAddon.fit();
      this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
      window.focus();
      this.term.focus();
    }, 100);

    // Global capture for Cmd+C / Cmd+V to bypass WebKit native consumption
    window.addEventListener('keydown', (e) => {
      // Cmd+C
      if ((e.code === 'KeyC' || e.key.toLowerCase() === 'c') && (e.metaKey || e.ctrlKey) && !e.shiftKey) {
        if (this.term && this.term.hasSelection()) {
          const text = this.term.getSelection();
          if (navigator.clipboard) {
            navigator.clipboard.writeText(text).catch(err => console.error(err));
          }
          this.pushEvent("clipboard_copy", { text: text });
          e.preventDefault();
          e.stopPropagation();
        }
      }
      // Cmd+V
      if ((e.code === 'KeyV' || e.key.toLowerCase() === 'v') && (e.metaKey || e.ctrlKey) && !e.shiftKey) {
        if (navigator.clipboard) {
          navigator.clipboard.readText().then(text => {
            if (this.term) this.term.paste(text);
          }).catch(() => {
            this.pushEvent("clipboard_paste", {});
          });
        } else {
          this.pushEvent("clipboard_paste", {});
        }
        e.preventDefault();
        e.stopPropagation();
      }
    }, true);

    // Custom Key Event Handler for Copy & Paste
    this.term.attachCustomKeyEventHandler(async (e) => {
      // Cmd+C or Ctrl+C to copy if text is selected
      if (e.type === 'keydown' && (e.code === 'KeyC' || e.key.toLowerCase() === 'c') && (e.metaKey || e.ctrlKey)) {
        if (this.term.hasSelection()) {
          const text = this.term.getSelection();
          if (navigator.clipboard) {
            navigator.clipboard.writeText(text).catch(err => console.error(err));
          }
          this.pushEvent("clipboard_copy", { text: text });
          return false; // Prevent default so it doesn't send Ctrl+C to the shell if selected
        }
      }
      
      // Cmd+V or Ctrl+V to paste
      if (e.type === 'keydown' && (e.code === 'KeyV' || e.key.toLowerCase() === 'v') && (e.metaKey || e.ctrlKey)) {
        if (navigator.clipboard) {
          navigator.clipboard.readText().then(text => {
            this.term.paste(text);
          }).catch(() => {
            this.pushEvent("clipboard_paste", {});
          });
        } else {
          this.pushEvent("clipboard_paste", {});
        }
        return false;
      }
      return true;
    });

    // Also listen to native copy events in case the terminal isn't perfectly focused
    window.addEventListener('copy', (e) => {
      if (this.term.hasSelection()) {
        this.pushEvent("clipboard_copy", { text: this.term.getSelection() });
        e.preventDefault();
      }
    });

    // Handle incoming events from LiveView
    this.handleEvent("request_copy", () => {
      if (this.term.hasSelection()) {
        const text = this.term.getSelection();
        if (navigator.clipboard) {
          navigator.clipboard.writeText(text).catch(err => console.error(err));
        }
        this.pushEvent("clipboard_copy", { text: text });
      }
    });

    this.handleEvent("request_paste", () => {
      if (navigator.clipboard) {
        navigator.clipboard.readText().then(text => {
          this.term.paste(text);
        }).catch(() => {
          this.pushEvent("clipboard_paste", {});
        });
      } else {
        this.pushEvent("clipboard_paste", {});
      }
    });
    // Handle incoming paste events from LiveView (fallback if navigator.clipboard fails)
    this.handleEvent("terminal_paste", (payload) => {
      if (payload.text) {
        this.term.paste(payload.text);
      }
    });
  }
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
});

liveSocket.connect();
