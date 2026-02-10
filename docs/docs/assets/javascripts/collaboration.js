/**
 * LiquorPro Documentation Collaboration System
 * - Integrated with LiquorPro authentication
 * - Text selection for contextual comments
 * - Real-time comment persistence
 * - Inline editing for Editor role
 */

(function() {
    'use strict';

    // Use relative URL for same-origin API calls
    const API_BASE = '/api';
    const STORAGE_KEY = 'liquorpro_docs_auth';

    // ===================
    // Authentication Manager
    // ===================
    class AuthManager {
        constructor() {
            this.user = null;
            this.token = null;
            this.docsAccess = null;
            this.loadFromStorage();
        }

        loadFromStorage() {
            try {
                const stored = localStorage.getItem(STORAGE_KEY);
                if (stored) {
                    const data = JSON.parse(stored);
                    this.user = data.user;
                    this.token = data.token;
                    this.docsAccess = data.docsAccess;
                }
            } catch (e) {
                console.error('Failed to load auth:', e);
            }
        }

        saveToStorage() {
            try {
                localStorage.setItem(STORAGE_KEY, JSON.stringify({
                    user: this.user,
                    token: this.token,
                    docsAccess: this.docsAccess
                }));
            } catch (e) {
                console.error('Failed to save auth:', e);
            }
        }

        isLoggedIn() {
            return !!(this.user && this.token);
        }

        hasDocsAccess() {
            return this.docsAccess && this.docsAccess.role;
        }

        canEdit() {
            return this.docsAccess && this.docsAccess.can_edit;
        }

        canComment() {
            return this.docsAccess && this.docsAccess.can_comment;
        }

        async login(email, password) {
            try {
                // Send both username and email for compatibility with backend validation
                const response = await fetch(`${API_BASE}/auth/login`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ username: email, email: email, password })
                });

                const data = await response.json();

                // Check for error responses (non-2xx status)
                if (!response.ok) {
                    // Parse specific error types for better UX
                    let errorMessage = data.error || data.message || 'Login failed';
                    let errorType = 'error';

                    // Handle validation errors
                    if (data.errors) {
                        const errors = Object.values(data.errors).flat();
                        errorMessage = errors.join('. ');
                        errorType = 'validation';
                    }

                    // Handle specific status codes
                    if (response.status === 400) {
                        if (errorMessage.toLowerCase().includes('user') ||
                            errorMessage.toLowerCase().includes('not found') ||
                            errorMessage.toLowerCase().includes('invalid')) {
                            errorMessage = 'Invalid email or password. Please check your credentials.';
                        }
                    } else if (response.status === 401) {
                        const remainingAttempts = data.remaining_attempts;
                        if (remainingAttempts !== undefined) {
                            errorMessage = `Invalid password. ${remainingAttempts} attempt${remainingAttempts !== 1 ? 's' : ''} remaining.`;
                        } else {
                            errorMessage = 'Invalid email or password.';
                        }
                        errorType = 'auth';
                    } else if (response.status === 423) {
                        const retryAfter = data.retry_after || data.remaining_lockout_seconds;
                        const minutes = Math.ceil(retryAfter / 60);
                        errorMessage = `Account temporarily locked. Try again in ${minutes} minute${minutes !== 1 ? 's' : ''}.`;
                        errorType = 'locked';
                    } else if (response.status === 409) {
                        errorMessage = 'Too many devices. Please logout from another device first.';
                        errorType = 'device_limit';
                    }

                    return {
                        success: false,
                        message: errorMessage,
                        type: errorType,
                        data: data
                    };
                }

                // Success response - handle both formats:
                // Format 1: { token, user, tenant } (direct)
                // Format 2: { success, data: { access_token, user } } (wrapped)
                if (data.token && data.user) {
                    this.user = data.user;
                    this.token = data.token;
                } else if (data.data && data.data.access_token) {
                    this.user = data.data.user;
                    this.token = data.data.access_token;
                } else {
                    console.error('Unexpected login response format:', data);
                    return {
                        success: false,
                        message: 'Unexpected server response. Please try again.',
                        type: 'error'
                    };
                }

                // Check docs access after login
                await this.checkDocsAccess();

                this.saveToStorage();
                return { success: true };

            } catch (e) {
                console.error('Login error:', e);
                return {
                    success: false,
                    message: 'Unable to connect to server. Please check your internet connection.',
                    type: 'network'
                };
            }
        }

        async checkDocsAccess() {
            if (!this.token) {
                this.docsAccess = null;
                return;
            }

            try {
                const response = await fetch(`${API_BASE}/docs/access/check`, {
                    headers: this.getAuthHeaders()
                });

                const data = await response.json();

                // Handle multiple response formats
                if (data.success && data.access) {
                    this.docsAccess = data.access;
                } else if (data.access) {
                    this.docsAccess = data.access;
                } else if (data.role) {
                    // Direct format
                    this.docsAccess = data;
                } else {
                    // If no docs access endpoint, grant based on user role
                    // Admin users get full access by default
                    if (this.user && (this.user.role === 'admin' || this.user.role === 'saas_admin')) {
                        this.docsAccess = {
                            role: 'editor',
                            can_edit: true,
                            can_comment: true
                        };
                    } else if (this.user) {
                        // Other logged in users can comment
                        this.docsAccess = {
                            role: 'commenter',
                            can_edit: false,
                            can_comment: true
                        };
                    } else {
                        this.docsAccess = null;
                    }
                }
            } catch (e) {
                console.error('Docs access check failed:', e);
                // Fallback: grant access based on user role
                if (this.user && (this.user.role === 'admin' || this.user.role === 'saas_admin')) {
                    this.docsAccess = {
                        role: 'editor',
                        can_edit: true,
                        can_comment: true
                    };
                } else if (this.user) {
                    this.docsAccess = {
                        role: 'commenter',
                        can_edit: false,
                        can_comment: true
                    };
                } else {
                    this.docsAccess = null;
                }
            }
        }

        logout() {
            this.user = null;
            this.token = null;
            this.docsAccess = null;
            localStorage.removeItem(STORAGE_KEY);
            window.location.reload();
        }

        getAuthHeaders() {
            const headers = { 'Content-Type': 'application/json' };
            if (this.token) {
                headers['Authorization'] = `Bearer ${this.token}`;
            }
            return headers;
        }
    }

    // ===================
    // Text Selection Manager (Enhanced)
    // ===================
    class TextSelectionManager {
        constructor() {
            this.currentSelection = null;
            this.selectionRange = null;
            this.highlightedElements = [];
            this.persistentHighlights = [];

            // Default colors
            this.highlightColors = {
                yellow: '#fff59d',
                green: '#a5d6a7',
                blue: '#90caf9',
                pink: '#f48fb1',
                orange: '#ffcc80',
                purple: '#ce93d8'
            };

            // Default color for comments vs highlights
            this.defaultCommentColor = '#90caf9';   // Blue for comments
            this.defaultHighlightColor = '#fff59d'; // Yellow for highlights
        }

        captureSelection() {
            const selection = window.getSelection();

            if (!selection || selection.isCollapsed || selection.rangeCount === 0) {
                this.currentSelection = null;
                this.selectionRange = null;
                return null;
            }

            const range = selection.getRangeAt(0);
            const selectedText = selection.toString().trim();

            if (!selectedText || selectedText.length < 3) {
                this.currentSelection = null;
                this.selectionRange = null;
                return null;
            }

            const container = range.commonAncestorContainer;
            const contentEl = container.nodeType === Node.TEXT_NODE
                ? container.parentElement
                : container;

            // Generate XPath for selection anchoring
            const xpath = this.getXPath(contentEl);

            // Store the range for highlighting
            this.selectionRange = range.cloneRange();

            // Get bounding rect for popup positioning
            const rects = range.getClientRects();
            const boundingRect = range.getBoundingClientRect();

            this.currentSelection = {
                text: selectedText,
                xpath: xpath,
                startOffset: range.startOffset,
                endOffset: range.endOffset,
                boundingRect: boundingRect,
                rects: Array.from(rects),
                range: range.cloneRange()
            };

            return this.currentSelection;
        }

        getXPath(element) {
            if (!element || element === document.body) return '/body';

            const parts = [];
            let current = element;

            while (current && current !== document.body) {
                let index = 1;
                let sibling = current.previousElementSibling;

                while (sibling) {
                    if (sibling.tagName === current.tagName) index++;
                    sibling = sibling.previousElementSibling;
                }

                const tagName = current.tagName.toLowerCase();
                parts.unshift(index > 1 ? `${tagName}[${index}]` : tagName);
                current = current.parentElement;
            }

            return '/body/' + parts.join('/');
        }

        // Apply persistent highlight with color
        applyHighlight(color = null, type = 'highlight', id = null) {
            if (!this.selectionRange) return null;

            const highlightColor = color || (type === 'comment' ? this.defaultCommentColor : this.defaultHighlightColor);

            try {
                const highlight = document.createElement('mark');
                highlight.className = `collab-highlight collab-highlight-${type}`;
                highlight.style.backgroundColor = highlightColor;
                highlight.style.padding = '2px 0';
                highlight.style.borderRadius = '2px';
                highlight.style.cursor = 'pointer';

                if (id) {
                    highlight.dataset.id = id;
                }
                highlight.dataset.type = type;
                highlight.dataset.color = highlightColor;

                this.selectionRange.surroundContents(highlight);
                this.persistentHighlights.push(highlight);

                // Add click handler to show related comment
                highlight.addEventListener('click', () => {
                    if (highlight.dataset.id) {
                        const event = new CustomEvent('highlight-click', {
                            detail: { id: highlight.dataset.id, type: highlight.dataset.type }
                        });
                        document.dispatchEvent(event);
                    }
                });

                return highlight;
            } catch (e) {
                // Complex selections spanning multiple elements - use CSS approach
                console.log('Complex selection, applying overlay highlight');
                return this.applyOverlayHighlight(highlightColor, type, id);
            }
        }

        // Apply overlay highlight for complex selections
        applyOverlayHighlight(color, type, id) {
            if (!this.currentSelection || !this.currentSelection.rects) return null;

            const container = document.createElement('div');
            container.className = `collab-highlight-overlay collab-highlight-${type}`;
            container.dataset.type = type;
            if (id) container.dataset.id = id;

            this.currentSelection.rects.forEach(rect => {
                const overlay = document.createElement('div');
                overlay.style.cssText = `
                    position: absolute;
                    left: ${rect.left + window.scrollX}px;
                    top: ${rect.top + window.scrollY}px;
                    width: ${rect.width}px;
                    height: ${rect.height}px;
                    background-color: ${color};
                    opacity: 0.4;
                    pointer-events: none;
                    z-index: 1;
                    border-radius: 2px;
                `;
                container.appendChild(overlay);
            });

            document.body.appendChild(container);
            this.persistentHighlights.push(container);
            return container;
        }

        // Highlight selected text temporarily (preview)
        highlightSelection(color = null) {
            if (!this.selectionRange) return;

            const highlightColor = color || this.defaultHighlightColor;

            try {
                const highlight = document.createElement('span');
                highlight.className = 'collab-temp-highlight';
                highlight.style.backgroundColor = highlightColor;
                this.selectionRange.surroundContents(highlight);
                this.highlightedElements.push(highlight);
            } catch (e) {
                console.log('Complex selection, using overlay highlight');
            }
        }

        // Remove temporary highlights
        removeHighlights() {
            this.highlightedElements.forEach(el => {
                if (el.parentNode) {
                    const parent = el.parentNode;
                    while (el.firstChild) {
                        parent.insertBefore(el.firstChild, el);
                    }
                    parent.removeChild(el);
                }
            });
            this.highlightedElements = [];
        }

        // Remove all persistent highlights
        clearPersistentHighlights() {
            this.persistentHighlights.forEach(el => {
                if (el.parentNode) {
                    if (el.tagName === 'MARK') {
                        const parent = el.parentNode;
                        while (el.firstChild) {
                            parent.insertBefore(el.firstChild, el);
                        }
                        parent.removeChild(el);
                    } else {
                        el.remove();
                    }
                }
            });
            this.persistentHighlights = [];
        }

        clear() {
            this.currentSelection = null;
            this.selectionRange = null;
            this.removeHighlights();
            window.getSelection().removeAllRanges();
        }

        getColorOptions() {
            return this.highlightColors;
        }
    }

    // ===================
    // Comments Manager (Backend-Integrated)
    // ===================
    class CommentsManager {
        constructor(auth, selectionManager) {
            this.auth = auth;
            this.selectionManager = selectionManager;
            this.pageId = this.getPageId();
            this.comments = [];
        }

        getPageId() {
            return window.location.pathname.replace(/\//g, '_').replace(/\.html$/, '');
        }

        async loadComments() {
            try {
                const response = await fetch(
                    `${API_BASE}/docs/comments?page_id=${encodeURIComponent(this.pageId)}`,
                    { headers: this.auth.getAuthHeaders() }
                );

                const data = await response.json();

                // Handle multiple response formats
                if (data.success && data.comments) {
                    this.comments = data.comments;
                } else if (data.comments) {
                    this.comments = data.comments;
                } else if (Array.isArray(data)) {
                    this.comments = data;
                } else {
                    this.comments = [];
                }
            } catch (e) {
                console.error('Failed to load comments:', e);
                this.comments = [];
            }

            return this.comments;
        }

        async addComment(content, parentId = null, highlightColor = null) {
            if (!this.auth.hasDocsAccess()) {
                throw new Error('Documentation access required');
            }

            const selection = this.selectionManager.currentSelection;

            const payload = {
                page_id: this.pageId,
                page_path: window.location.pathname,
                content: content,
            };

            if (parentId) {
                payload.parent_id = parentId;
            }

            // Include selection data if text was selected
            if (selection) {
                payload.selection = selection.text;
                payload.selection_xpath = selection.xpath;
                payload.start_offset = selection.startOffset;
                payload.end_offset = selection.endOffset;
            }

            // Include highlight color if provided
            if (highlightColor) {
                payload.highlight_color = highlightColor;
            }

            try {
                const response = await fetch(`${API_BASE}/docs/comments`, {
                    method: 'POST',
                    headers: this.auth.getAuthHeaders(),
                    body: JSON.stringify(payload)
                });

                const data = await response.json();

                if (!response.ok) {
                    throw new Error(data.error || 'Failed to save comment');
                }

                // Handle multiple response formats
                let comment = null;
                if (data.success && data.comment) {
                    comment = data.comment;
                } else if (data.comment) {
                    comment = data.comment;
                } else if (data.id) {
                    comment = data;
                }

                if (comment) {
                    this.comments.push(comment);
                    this.selectionManager.clear();
                    return comment;
                }

                throw new Error('Invalid response from server');

            } catch (e) {
                console.error('Failed to add comment:', e);
                throw e;
            }
        }

        async addHighlight(color = '#ffeb3b') {
            const selection = this.selectionManager.currentSelection;
            if (!selection) return null;

            const payload = {
                page_id: this.pageId,
                page_path: window.location.pathname,
                type: 'highlight',
                selection: selection.text,
                selection_xpath: selection.xpath,
                start_offset: selection.startOffset,
                end_offset: selection.endOffset,
                highlight_color: color
            };

            try {
                const response = await fetch(`${API_BASE}/docs/highlights`, {
                    method: 'POST',
                    headers: this.auth.getAuthHeaders(),
                    body: JSON.stringify(payload)
                });

                if (response.ok) {
                    const data = await response.json();
                    this.selectionManager.clear();
                    return data.highlight || data;
                }
            } catch (e) {
                console.error('Failed to save highlight:', e);
            }

            // Even if save fails, apply highlight locally
            return { local: true, color, selection };
        }

        async resolveComment(commentId) {
            try {
                const response = await fetch(
                    `${API_BASE}/docs/comments/${commentId}/resolve`,
                    {
                        method: 'POST',
                        headers: this.auth.getAuthHeaders()
                    }
                );

                const data = await response.json();

                if (data.success) {
                    const comment = this.comments.find(c => c.id === commentId);
                    if (comment) {
                        comment.is_resolved = true;
                        comment.resolved_at = new Date().toISOString();
                    }
                }
                return data.success;
            } catch (e) {
                console.error('Failed to resolve comment:', e);
                return false;
            }
        }
    }

    // ===================
    // Inline Editor (for Editor role)
    // ===================
    class InlineEditor {
        constructor(auth) {
            this.auth = auth;
            this.isEditing = false;
            this.originalContent = null;
        }

        canEdit() {
            return this.auth.canEdit();
        }

        initEditor() {
            if (!this.canEdit()) return;

            const contentArea = document.querySelector('.md-content__inner');
            if (!contentArea) return;

            const editBtn = document.createElement('button');
            editBtn.id = 'inline-edit-btn';
            editBtn.className = 'collab-btn collab-btn-edit';
            editBtn.innerHTML = `
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M12 20h9"/>
                    <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
                </svg>
                Edit Page
            `;
            editBtn.onclick = () => this.toggleEditMode();

            contentArea.style.position = 'relative';
            contentArea.insertBefore(editBtn, contentArea.firstChild);
        }

        toggleEditMode() {
            if (this.isEditing) {
                this.exitEditMode();
            } else {
                this.enterEditMode();
            }
        }

        enterEditMode() {
            const contentArea = document.querySelector('.md-content__inner article');
            if (!contentArea) return;

            this.originalContent = contentArea.innerHTML;
            this.isEditing = true;

            contentArea.contentEditable = true;
            contentArea.classList.add('collab-editing');

            const btn = document.getElementById('inline-edit-btn');
            btn.innerHTML = `
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/>
                    <polyline points="17 21 17 13 7 13 7 21"/>
                </svg>
                Save Changes
            `;
            btn.classList.add('collab-btn-save');

            const cancelBtn = document.createElement('button');
            cancelBtn.id = 'inline-cancel-btn';
            cancelBtn.className = 'collab-btn collab-btn-cancel';
            cancelBtn.textContent = 'Cancel';
            cancelBtn.onclick = () => this.cancelEdit();
            btn.parentNode.insertBefore(cancelBtn, btn.nextSibling);

            this.addFormattingToolbar(contentArea);
        }

        addFormattingToolbar(contentArea) {
            const toolbar = document.createElement('div');
            toolbar.id = 'collab-edit-toolbar';
            toolbar.className = 'collab-toolbar';
            toolbar.innerHTML = `
                <button data-cmd="bold" title="Bold"><b>B</b></button>
                <button data-cmd="italic" title="Italic"><i>I</i></button>
                <button data-cmd="insertUnorderedList" title="Bullet List">&#8226;</button>
                <button data-cmd="insertOrderedList" title="Numbered List">1.</button>
                <button data-cmd="formatBlock" data-value="h2" title="Heading">H2</button>
                <button data-cmd="formatBlock" data-value="h3" title="Subheading">H3</button>
                <button data-cmd="createLink" title="Add Link">&#128279;</button>
            `;

            contentArea.parentNode.insertBefore(toolbar, contentArea);

            toolbar.querySelectorAll('button').forEach(btn => {
                btn.onclick = (e) => {
                    e.preventDefault();
                    const cmd = btn.dataset.cmd;
                    const value = btn.dataset.value || null;

                    if (cmd === 'createLink') {
                        const url = prompt('Enter URL:');
                        if (url) document.execCommand(cmd, false, url);
                    } else if (cmd === 'formatBlock') {
                        document.execCommand(cmd, false, `<${value}>`);
                    } else {
                        document.execCommand(cmd, false, value);
                    }
                };
            });
        }

        async exitEditMode() {
            const contentArea = document.querySelector('.md-content__inner article');
            if (!contentArea) return;

            const newContent = contentArea.innerHTML;

            if (newContent !== this.originalContent) {
                const success = await this.saveEdit(newContent);
                if (!success) {
                    if (!confirm('Failed to save. Discard changes?')) {
                        return;
                    }
                }
            }

            this.cleanupEditMode(contentArea);
        }

        cancelEdit() {
            const contentArea = document.querySelector('.md-content__inner article');
            if (!contentArea) return;

            if (this.originalContent) {
                contentArea.innerHTML = this.originalContent;
            }

            this.cleanupEditMode(contentArea);
        }

        cleanupEditMode(contentArea) {
            contentArea.contentEditable = false;
            contentArea.classList.remove('collab-editing');
            this.isEditing = false;

            const toolbar = document.getElementById('collab-edit-toolbar');
            if (toolbar) toolbar.remove();

            const cancelBtn = document.getElementById('inline-cancel-btn');
            if (cancelBtn) cancelBtn.remove();

            const btn = document.getElementById('inline-edit-btn');
            if (btn) {
                btn.innerHTML = `
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M12 20h9"/>
                        <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
                    </svg>
                    Edit Page
                `;
                btn.classList.remove('collab-btn-save');
            }
        }

        async saveEdit(newContent) {
            const pagePath = window.location.pathname;
            const filePath = this.pagePathToFilePath(pagePath);

            try {
                const response = await fetch(`${API_BASE}/docs/edits`, {
                    method: 'POST',
                    headers: this.auth.getAuthHeaders(),
                    body: JSON.stringify({
                        page_id: pagePath.replace(/\//g, '_').replace(/\.html$/, ''),
                        page_path: pagePath,
                        file_path: filePath,
                        new_content: newContent
                    })
                });

                const data = await response.json();

                if (data.success) {
                    this.showNotification('Changes saved successfully!', 'success');
                    return true;
                } else {
                    this.showNotification(data.error || 'Failed to save', 'error');
                    return false;
                }
            } catch (e) {
                console.error('Save error:', e);
                this.showNotification('Network error while saving', 'error');
                return false;
            }
        }

        pagePathToFilePath(pagePath) {
            let mdPath = pagePath
                .replace(/^\//, '')
                .replace(/\/$/, '')
                .replace(/\.html$/, '');

            if (!mdPath || mdPath === 'index') {
                mdPath = 'index';
            }

            return `/var/www/liquorpro/docs/docs/${mdPath}.md`;
        }

        showNotification(message, type) {
            const notification = document.createElement('div');
            notification.className = `collab-notification collab-notification-${type}`;
            notification.textContent = message;
            document.body.appendChild(notification);

            setTimeout(() => notification.remove(), 3000);
        }
    }

    // ===================
    // UI Components
    // ===================
    class CollaborationUI {
        constructor(auth, comments, editor, selectionManager) {
            this.auth = auth;
            this.comments = comments;
            this.editor = editor;
            this.selectionManager = selectionManager;
        }

        async init() {
            injectStyles();

            if (this.auth.isLoggedIn()) {
                await this.auth.checkDocsAccess();
                this.auth.saveToStorage();
            }

            this.createAuthBar();
            this.createCommentsPanel();
            this.setupTextSelectionHandler();

            if (this.auth.canEdit()) {
                this.editor.initEditor();
            }

            await this.loadAndRenderComments();
        }

        setupTextSelectionHandler() {
            let selectionTimeout = null;

            // Handle mouse up for text selection
            document.addEventListener('mouseup', (e) => {
                // Ignore clicks on UI elements
                if (e.target.closest('#collab-auth-bar, #collab-comments-panel, .collab-modal, .collab-inline-comment-box, .collab-selection-toolbar')) {
                    return;
                }

                // Debounce to avoid flickering
                clearTimeout(selectionTimeout);
                selectionTimeout = setTimeout(() => {
                    const selection = this.selectionManager.captureSelection();

                    if (selection && this.auth.canComment()) {
                        this.showSelectionToolbar(selection);
                    } else {
                        this.hideSelectionToolbar();
                    }
                }, 10);
            });

            // Hide toolbar on scroll
            document.addEventListener('scroll', () => {
                this.hideSelectionToolbar();
            }, { passive: true });

            // Handle keyboard selection (Shift+Arrow keys)
            document.addEventListener('keyup', (e) => {
                if (e.shiftKey || e.key === 'Shift') {
                    const selection = this.selectionManager.captureSelection();
                    if (selection && this.auth.canComment()) {
                        this.showSelectionToolbar(selection);
                    }
                }
            });
        }

        showSelectionToolbar(selection) {
            this.hideSelectionToolbar();
            this.hideInlineCommentBox();

            const rect = selection.boundingRect;
            if (!rect || rect.width === 0) return;

            const toolbar = document.createElement('div');
            toolbar.id = 'collab-selection-toolbar';
            toolbar.className = 'collab-selection-toolbar';

            // Calculate position - above the selection, centered
            const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
            const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;

            let top = rect.top + scrollTop - 50;
            let left = rect.left + scrollLeft + (rect.width / 2);

            // Ensure toolbar stays within viewport
            const viewportWidth = window.innerWidth;
            if (left < 120) left = 120;
            if (left > viewportWidth - 120) left = viewportWidth - 120;
            if (top < 60) top = rect.bottom + scrollTop + 10; // Show below if no space above

            // Get color options
            const colors = this.selectionManager.getColorOptions();
            const colorButtons = Object.entries(colors).map(([name, color]) =>
                `<button class="collab-color-btn" data-color="${color}" title="${name}" style="background-color: ${color};"></button>`
            ).join('');

            toolbar.innerHTML = `
                <div class="collab-toolbar-content">
                    <button class="collab-toolbar-btn collab-toolbar-btn-comment" data-action="comment">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
                        </svg>
                        <span>Comment</span>
                    </button>
                    <div class="collab-toolbar-divider"></div>
                    <button class="collab-toolbar-btn collab-toolbar-btn-highlight" data-action="highlight">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M9.5 2l6 6-6 6-6-6 6-6z"/>
                            <path d="M21 14l-6 6H9l6-6"/>
                            <path d="M14 4l6 6"/>
                        </svg>
                        <span>Highlight</span>
                    </button>
                </div>
                <div class="collab-color-picker" style="display: none;">
                    <div class="collab-color-label">Pick a color:</div>
                    <div class="collab-color-options">
                        ${colorButtons}
                    </div>
                </div>
                <div class="collab-toolbar-arrow"></div>
            `;

            toolbar.style.cssText = `
                position: absolute;
                left: ${left}px;
                top: ${top}px;
                transform: translateX(-50%);
                z-index: 10001;
            `;

            document.body.appendChild(toolbar);

            // Animate in
            requestAnimationFrame(() => {
                toolbar.classList.add('collab-toolbar-visible');
            });

            const colorPicker = toolbar.querySelector('.collab-color-picker');
            let selectedColor = this.selectionManager.defaultHighlightColor;
            let actionType = null;

            // Bind actions
            toolbar.querySelector('[data-action="comment"]').onclick = (e) => {
                e.stopPropagation();
                this.showInlineCommentBox(selection, rect);
            };

            toolbar.querySelector('[data-action="highlight"]').onclick = (e) => {
                e.stopPropagation();
                actionType = 'highlight';
                colorPicker.style.display = 'block';
                toolbar.classList.add('collab-toolbar-expanded');
            };

            // Color selection
            toolbar.querySelectorAll('.collab-color-btn').forEach(btn => {
                btn.onclick = (e) => {
                    e.stopPropagation();
                    selectedColor = btn.dataset.color;

                    // Apply persistent highlight
                    this.selectionManager.applyHighlight(selectedColor, 'highlight');
                    this.hideSelectionToolbar();

                    // Save highlight to backend
                    this.comments.addHighlight(selectedColor).catch(err => {
                        console.log('Highlight saved locally only:', err);
                    });
                };
            });

            // Auto-hide on click outside
            setTimeout(() => {
                const hideHandler = (e) => {
                    if (!e.target.closest('.collab-selection-toolbar, .collab-inline-comment-box')) {
                        this.hideSelectionToolbar();
                        document.removeEventListener('mousedown', hideHandler);
                    }
                };
                document.addEventListener('mousedown', hideHandler);
            }, 100);
        }

        hideSelectionToolbar() {
            const existing = document.getElementById('collab-selection-toolbar');
            if (existing) {
                existing.classList.remove('collab-toolbar-visible');
                setTimeout(() => existing.remove(), 150);
            }
        }

        showInlineCommentBox(selection, rect) {
            this.hideSelectionToolbar();
            this.hideInlineCommentBox();

            const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
            const scrollLeft = window.pageXOffset || document.documentElement.scrollLeft;

            const box = document.createElement('div');
            box.id = 'collab-inline-comment-box';
            box.className = 'collab-inline-comment-box';

            const truncatedText = selection.text.length > 80
                ? selection.text.substring(0, 80) + '...'
                : selection.text;

            box.innerHTML = `
                <div class="collab-inline-header">
                    <div class="collab-inline-quote">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                            <path d="M6 17h3l2-4V7H5v6h3zm8 0h3l2-4V7h-6v6h3z"/>
                        </svg>
                        <span>"${this.escapeHtml(truncatedText)}"</span>
                    </div>
                    <button class="collab-inline-close" aria-label="Close">&times;</button>
                </div>
                <div class="collab-inline-body">
                    <textarea
                        class="collab-inline-textarea"
                        placeholder="Add your comment..."
                        rows="3"
                        autofocus
                    ></textarea>
                    <div class="collab-inline-actions">
                        <button class="collab-inline-cancel">Cancel</button>
                        <button class="collab-inline-submit">
                            <span class="collab-inline-submit-text">Post Comment</span>
                            <span class="collab-inline-submit-loading" style="display:none;">
                                <svg class="collab-spinner" width="16" height="16" viewBox="0 0 24 24">
                                    <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3" fill="none" stroke-dasharray="31.4 31.4" stroke-linecap="round"/>
                                </svg>
                                Posting...
                            </span>
                        </button>
                    </div>
                </div>
            `;

            // Position near the selection
            let top = rect.bottom + scrollTop + 10;
            let left = rect.left + scrollLeft;

            // Ensure box stays within viewport
            const viewportWidth = window.innerWidth;
            const boxWidth = 360;
            if (left + boxWidth > viewportWidth - 20) {
                left = viewportWidth - boxWidth - 20;
            }
            if (left < 20) left = 20;

            box.style.cssText = `
                position: absolute;
                left: ${left}px;
                top: ${top}px;
                z-index: 10002;
            `;

            document.body.appendChild(box);

            // Animate in
            requestAnimationFrame(() => {
                box.classList.add('collab-inline-visible');
            });

            // Focus textarea
            const textarea = box.querySelector('.collab-inline-textarea');
            setTimeout(() => textarea.focus(), 100);

            // Bind events
            box.querySelector('.collab-inline-close').onclick = () => this.hideInlineCommentBox();
            box.querySelector('.collab-inline-cancel').onclick = () => this.hideInlineCommentBox();

            // Handle Escape key
            textarea.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    this.hideInlineCommentBox();
                } else if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
                    // Cmd/Ctrl + Enter to submit
                    box.querySelector('.collab-inline-submit').click();
                }
            });

            // Submit handler
            box.querySelector('.collab-inline-submit').onclick = async () => {
                const content = textarea.value.trim();
                if (!content) {
                    textarea.classList.add('collab-inline-error');
                    textarea.placeholder = 'Please enter a comment...';
                    setTimeout(() => {
                        textarea.classList.remove('collab-inline-error');
                        textarea.placeholder = 'Add your comment...';
                    }, 2000);
                    return;
                }

                const submitBtn = box.querySelector('.collab-inline-submit');
                const submitText = box.querySelector('.collab-inline-submit-text');
                const submitLoading = box.querySelector('.collab-inline-submit-loading');

                try {
                    submitBtn.disabled = true;
                    submitText.style.display = 'none';
                    submitLoading.style.display = 'flex';

                    await this.comments.addComment(content);

                    // Success feedback
                    box.classList.add('collab-inline-success');
                    box.querySelector('.collab-inline-body').innerHTML = `
                        <div class="collab-inline-success-message">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
                                <polyline points="22 4 12 14.01 9 11.01"/>
                            </svg>
                            <span>Comment posted successfully!</span>
                        </div>
                    `;

                    // Refresh comments panel
                    await this.loadAndRenderComments();

                    // Close after brief delay
                    setTimeout(() => this.hideInlineCommentBox(), 1500);

                } catch (e) {
                    submitBtn.disabled = false;
                    submitText.style.display = 'inline';
                    submitLoading.style.display = 'none';

                    // Show error
                    const errorDiv = document.createElement('div');
                    errorDiv.className = 'collab-inline-error-message';
                    errorDiv.textContent = e.message || 'Failed to post comment';
                    box.querySelector('.collab-inline-actions').prepend(errorDiv);

                    setTimeout(() => errorDiv.remove(), 3000);
                }
            };
        }

        hideInlineCommentBox() {
            const existing = document.getElementById('collab-inline-comment-box');
            if (existing) {
                existing.classList.remove('collab-inline-visible');
                setTimeout(() => existing.remove(), 150);
            }
            this.selectionManager.clear();
        }

        // Legacy method for panel-based commenting (kept for compatibility)
        openCommentPanelWithSelection(selection) {
            const panel = document.getElementById('collab-comments-panel');
            panel.classList.remove('collab-panel-hidden');

            const preview = document.getElementById('selection-preview');
            if (preview && selection) {
                const truncated = selection.text.length > 100
                    ? selection.text.substring(0, 100) + '...'
                    : selection.text;
                preview.innerHTML = `
                    <div class="collab-selection-preview">
                        <strong>Commenting on:</strong>
                        <blockquote>"${this.escapeHtml(truncated)}"</blockquote>
                    </div>
                `;
                preview.style.display = 'block';
            }

            const textarea = document.getElementById('collab-comment-input');
            if (textarea) textarea.focus();
        }

        createAuthBar() {
            const authBar = document.createElement('div');
            authBar.id = 'collab-auth-bar';

            if (this.auth.isLoggedIn()) {
                if (this.auth.hasDocsAccess()) {
                    authBar.innerHTML = this.getLoggedInWithAccessUI();
                } else {
                    authBar.innerHTML = this.getLoggedInNoAccessUI();
                }
            } else {
                authBar.innerHTML = this.getLoginUI();
            }

            document.body.appendChild(authBar);
            this.bindAuthEvents();
        }

        getLoggedInWithAccessUI() {
            const name = this.auth.user?.first_name || this.auth.user?.email || 'User';
            const role = this.auth.docsAccess.role === 'editor' ? 'Editor' : 'Viewer';
            const initial = name.charAt(0).toUpperCase();

            return `
                <div class="collab-auth-content">
                    <div class="collab-user-info">
                        <div class="collab-avatar">${initial}</div>
                        <span class="collab-user-name">${name}</span>
                        <span class="collab-role-badge collab-role-${role.toLowerCase()}">${role}</span>
                    </div>
                    <button id="collab-comments-toggle" class="collab-btn">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
                        </svg>
                        Comments <span id="comment-count" class="collab-badge">0</span>
                    </button>
                    <button id="collab-logout-btn" class="collab-btn collab-btn-secondary">Logout</button>
                </div>
            `;
        }

        getLoggedInNoAccessUI() {
            return `
                <div class="collab-auth-content">
                    <span class="collab-no-access">You are logged in but don't have documentation access. Contact an admin.</span>
                    <button id="collab-logout-btn" class="collab-btn collab-btn-secondary">Logout</button>
                </div>
            `;
        }

        getLoginUI() {
            return `
                <div class="collab-auth-content">
                    <button id="collab-login-btn" class="collab-btn collab-btn-primary">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
                            <circle cx="12" cy="7" r="4"/>
                        </svg>
                        Login to Comment & Edit
                    </button>
                </div>
            `;
        }

        createCommentsPanel() {
            const panel = document.createElement('div');
            panel.id = 'collab-comments-panel';
            panel.className = 'collab-panel-hidden';

            const canComment = this.auth.canComment();

            panel.innerHTML = `
                <div class="collab-panel-header">
                    <h3>Comments</h3>
                    <button id="collab-panel-close" class="collab-close-btn">&times;</button>
                </div>
                <div id="selection-preview" style="display:none;"></div>
                <div id="collab-comments-list" class="collab-comments-list">
                    <div class="collab-loading">Loading comments...</div>
                </div>
                ${canComment ? `
                <div class="collab-comment-form">
                    <textarea id="collab-comment-input" placeholder="Add a comment..." rows="3"></textarea>
                    <div class="collab-form-actions">
                        <button id="collab-submit-comment" class="collab-btn collab-btn-primary">Post Comment</button>
                    </div>
                </div>
                ` : `
                <div class="collab-login-prompt">
                    ${this.auth.isLoggedIn() ? 'Documentation access required to comment' : 'Login to add comments'}
                </div>
                `}
            `;

            document.body.appendChild(panel);
            this.bindPanelEvents();
        }

        bindAuthEvents() {
            const loginBtn = document.getElementById('collab-login-btn');
            const logoutBtn = document.getElementById('collab-logout-btn');
            const toggleBtn = document.getElementById('collab-comments-toggle');

            if (loginBtn) {
                loginBtn.onclick = () => this.showLoginModal();
            }

            if (logoutBtn) {
                logoutBtn.onclick = () => this.auth.logout();
            }

            if (toggleBtn) {
                toggleBtn.onclick = () => {
                    const panel = document.getElementById('collab-comments-panel');
                    panel.classList.toggle('collab-panel-hidden');
                    const preview = document.getElementById('selection-preview');
                    if (preview) preview.style.display = 'none';
                };
            }
        }

        bindPanelEvents() {
            const closeBtn = document.getElementById('collab-panel-close');
            const submitBtn = document.getElementById('collab-submit-comment');

            if (closeBtn) {
                closeBtn.onclick = () => {
                    document.getElementById('collab-comments-panel').classList.add('collab-panel-hidden');
                };
            }

            if (submitBtn) {
                submitBtn.onclick = async () => {
                    const input = document.getElementById('collab-comment-input');
                    const content = input.value.trim();

                    if (!content) {
                        alert('Please enter a comment');
                        return;
                    }

                    try {
                        submitBtn.disabled = true;
                        submitBtn.textContent = 'Posting...';

                        await this.comments.addComment(content);
                        input.value = '';

                        const preview = document.getElementById('selection-preview');
                        if (preview) preview.style.display = 'none';

                        await this.loadAndRenderComments();

                    } catch (e) {
                        alert('Failed to post comment: ' + e.message);
                    } finally {
                        submitBtn.disabled = false;
                        submitBtn.textContent = 'Post Comment';
                    }
                };
            }
        }

        showLoginModal() {
            const modal = document.createElement('div');
            modal.id = 'collab-login-modal';
            modal.className = 'collab-modal';
            modal.innerHTML = `
                <div class="collab-modal-content collab-login-modal-content">
                    <div class="collab-modal-header">
                        <h3>Login to LiquorPro Docs</h3>
                        <button class="collab-close-btn" onclick="this.closest('.collab-modal').remove()">&times;</button>
                    </div>
                    <div class="collab-modal-body">
                        <p class="collab-login-description">Use your LiquorPro credentials to access documentation features like commenting and editing.</p>
                        <div id="login-error" class="collab-login-error" style="display: none">
                            <div class="collab-error-icon">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <circle cx="12" cy="12" r="10"/>
                                    <line x1="12" y1="8" x2="12" y2="12"/>
                                    <line x1="12" y1="16" x2="12.01" y2="16"/>
                                </svg>
                            </div>
                            <span class="collab-error-text"></span>
                        </div>
                        <div class="collab-form-group">
                            <label for="login-email">Email Address</label>
                            <input type="email" id="login-email" placeholder="Enter your email" autocomplete="email">
                        </div>
                        <div class="collab-form-group">
                            <label for="login-password">Password</label>
                            <div class="collab-password-wrapper">
                                <input type="password" id="login-password" placeholder="Enter your password" autocomplete="current-password">
                                <button type="button" class="collab-password-toggle" aria-label="Toggle password visibility">
                                    <svg class="collab-eye-open" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
                                        <circle cx="12" cy="12" r="3"/>
                                    </svg>
                                    <svg class="collab-eye-closed" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="display:none">
                                        <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/>
                                        <line x1="1" y1="1" x2="23" y2="23"/>
                                    </svg>
                                </button>
                            </div>
                        </div>
                        <button id="login-submit" class="collab-btn collab-btn-primary collab-btn-full collab-login-btn">
                            <span class="collab-login-btn-text">Login</span>
                            <span class="collab-login-btn-loading" style="display:none">
                                <svg class="collab-spinner" width="18" height="18" viewBox="0 0 24 24">
                                    <circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3" fill="none" stroke-dasharray="31.4 31.4" stroke-linecap="round"/>
                                </svg>
                                Logging in...
                            </span>
                        </button>
                        <p class="collab-login-help">
                            Don't have an account? Contact your administrator for access.
                        </p>
                    </div>
                </div>
            `;
            document.body.appendChild(modal);
            this.bindLoginModalEvents(modal);

            // Focus email input
            setTimeout(() => modal.querySelector('#login-email').focus(), 100);
        }

        bindLoginModalEvents(modal) {
            const submitBtn = modal.querySelector('#login-submit');
            const emailInput = modal.querySelector('#login-email');
            const passwordInput = modal.querySelector('#login-password');
            const errorDiv = modal.querySelector('#login-error');
            const errorText = modal.querySelector('.collab-error-text');
            const passwordToggle = modal.querySelector('.collab-password-toggle');
            const eyeOpen = modal.querySelector('.collab-eye-open');
            const eyeClosed = modal.querySelector('.collab-eye-closed');
            const btnText = modal.querySelector('.collab-login-btn-text');
            const btnLoading = modal.querySelector('.collab-login-btn-loading');

            // Password visibility toggle
            passwordToggle.onclick = () => {
                const isPassword = passwordInput.type === 'password';
                passwordInput.type = isPassword ? 'text' : 'password';
                eyeOpen.style.display = isPassword ? 'none' : 'block';
                eyeClosed.style.display = isPassword ? 'block' : 'none';
            };

            const showError = (message, type = 'error') => {
                errorText.textContent = message;
                errorDiv.style.display = 'flex';
                errorDiv.className = `collab-login-error collab-login-error-${type}`;

                // Animate shake
                errorDiv.classList.add('collab-shake');
                setTimeout(() => errorDiv.classList.remove('collab-shake'), 500);
            };

            const hideError = () => {
                errorDiv.style.display = 'none';
            };

            const setLoading = (loading) => {
                submitBtn.disabled = loading;
                btnText.style.display = loading ? 'none' : 'inline';
                btnLoading.style.display = loading ? 'flex' : 'none';
            };

            const doLogin = async () => {
                const email = emailInput.value.trim();
                const password = passwordInput.value;

                hideError();

                // Client-side validation
                if (!email) {
                    showError('Please enter your email address', 'validation');
                    emailInput.focus();
                    return;
                }

                if (!email.includes('@') || !email.includes('.')) {
                    showError('Please enter a valid email address', 'validation');
                    emailInput.focus();
                    return;
                }

                if (!password) {
                    showError('Please enter your password', 'validation');
                    passwordInput.focus();
                    return;
                }

                if (password.length < 6) {
                    showError('Password must be at least 6 characters', 'validation');
                    passwordInput.focus();
                    return;
                }

                setLoading(true);

                const result = await this.auth.login(email, password);

                if (result.success) {
                    // Success animation before reload
                    submitBtn.classList.add('collab-login-success');
                    btnText.textContent = 'Success!';
                    btnText.style.display = 'inline';
                    btnLoading.style.display = 'none';

                    setTimeout(() => {
                        modal.remove();
                        window.location.reload();
                    }, 500);
                } else {
                    setLoading(false);
                    showError(result.message, result.type || 'error');

                    // Clear password on auth errors
                    if (result.type === 'auth' || result.type === 'error') {
                        passwordInput.value = '';
                        passwordInput.focus();
                    }
                }
            };

            // Clear errors on input
            emailInput.addEventListener('input', hideError);
            passwordInput.addEventListener('input', hideError);

            submitBtn.onclick = doLogin;
            emailInput.addEventListener('keypress', e => { if (e.key === 'Enter') passwordInput.focus(); });
            passwordInput.addEventListener('keypress', e => { if (e.key === 'Enter') doLogin(); });
            modal.onclick = e => { if (e.target === modal) modal.remove(); };

            // Handle Escape key
            modal.addEventListener('keydown', e => { if (e.key === 'Escape') modal.remove(); });
        }

        async loadAndRenderComments() {
            const comments = await this.comments.loadComments();
            const list = document.getElementById('collab-comments-list');
            const countBadge = document.getElementById('comment-count');

            console.log('Loaded comments:', comments.length);

            if (countBadge) {
                countBadge.textContent = comments.length;
            }

            if (!list) {
                console.error('Comments list element not found');
                return;
            }

            if (comments.length === 0) {
                list.innerHTML = '<div class="collab-no-comments">No comments yet. Select text to add a comment!</div>';
                return;
            }

            const topLevel = comments.filter(c => !c.parent_id);

            list.innerHTML = topLevel
                .map(c => this.renderComment(c, comments))
                .join('');

            this.bindCommentActions();

            // Apply highlights for comments with selections
            this.applyCommentHighlights(comments);
        }

        applyCommentHighlights(comments) {
            // Find and highlight text for each comment with selection
            comments.forEach(comment => {
                if (comment.selection && comment.selection.trim()) {
                    this.highlightCommentedText(comment);
                }
            });
        }

        highlightCommentedText(comment) {
            const searchText = comment.selection;
            if (!searchText || searchText.length < 3) return;

            const contentArea = document.querySelector('.md-content__inner article') ||
                               document.querySelector('.md-content__inner') ||
                               document.querySelector('article') ||
                               document.querySelector('main');

            if (!contentArea) return;

            // Use TreeWalker to find text nodes
            const walker = document.createTreeWalker(
                contentArea,
                NodeFilter.SHOW_TEXT,
                null,
                false
            );

            let node;
            while (node = walker.nextNode()) {
                const text = node.textContent;
                const index = text.indexOf(searchText);

                if (index !== -1) {
                    try {
                        const range = document.createRange();
                        range.setStart(node, index);
                        range.setEnd(node, index + searchText.length);

                        const highlight = document.createElement('mark');
                        highlight.className = 'collab-highlight collab-highlight-comment';
                        highlight.style.backgroundColor = comment.highlight_color || this.selectionManager.defaultCommentColor;
                        highlight.style.cursor = 'pointer';
                        highlight.dataset.commentId = comment.id;
                        highlight.title = `Comment by ${comment.user_name || 'User'}: ${comment.content.substring(0, 50)}...`;

                        highlight.onclick = () => {
                            // Open comments panel and scroll to this comment
                            const panel = document.getElementById('collab-comments-panel');
                            panel.classList.remove('collab-panel-hidden');
                            const commentEl = document.querySelector(`.collab-comment[data-id="${comment.id}"]`);
                            if (commentEl) {
                                commentEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
                                commentEl.classList.add('collab-comment-highlight');
                                setTimeout(() => commentEl.classList.remove('collab-comment-highlight'), 2000);
                            }
                        };

                        range.surroundContents(highlight);
                        break; // Only highlight first occurrence
                    } catch (e) {
                        console.log('Could not highlight text:', e.message);
                    }
                }
            }
        }

        renderComment(comment, allComments) {
            const replies = allComments.filter(c => c.parent_id === comment.id);
            const date = new Date(comment.created_at).toLocaleDateString();
            const userName = comment.user_name || 'Anonymous';
            const initial = userName.charAt(0).toUpperCase();
            const hasSelection = comment.selection && comment.selection.trim();

            return `
                <div class="collab-comment ${comment.is_resolved ? 'collab-comment-resolved' : ''}" data-id="${comment.id}">
                    <div class="collab-comment-header">
                        <div class="collab-avatar-small">${initial}</div>
                        <span class="collab-comment-author">${this.escapeHtml(userName)}</span>
                        <span class="collab-comment-date">${date}</span>
                        ${comment.is_resolved ? '<span class="collab-tag collab-tag-resolved">Resolved</span>' : ''}
                    </div>
                    ${hasSelection ? `
                        <div class="collab-comment-selection">
                            <blockquote>"${this.escapeHtml(comment.selection.substring(0, 100))}${comment.selection.length > 100 ? '...' : ''}"</blockquote>
                        </div>
                    ` : ''}
                    <div class="collab-comment-content">${this.escapeHtml(comment.content).replace(/\n/g, '<br>')}</div>
                    <div class="collab-comment-actions">
                        ${this.auth.canComment() && !comment.is_resolved ? `
                            <button class="collab-action-btn" data-action="reply" data-id="${comment.id}">Reply</button>
                            <button class="collab-action-btn" data-action="resolve" data-id="${comment.id}">Resolve</button>
                        ` : ''}
                    </div>
                    ${replies.length > 0 ? `
                        <div class="collab-replies">
                            ${replies.map(r => this.renderComment(r, allComments)).join('')}
                        </div>
                    ` : ''}
                </div>
            `;
        }

        escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        bindCommentActions() {
            document.querySelectorAll('.collab-action-btn').forEach(btn => {
                btn.onclick = async () => {
                    const action = btn.dataset.action;
                    const id = btn.dataset.id;

                    if (action === 'resolve') {
                        if (await this.comments.resolveComment(id)) {
                            this.loadAndRenderComments();
                        }
                    } else if (action === 'reply') {
                        const content = prompt('Enter your reply:');
                        if (content && content.trim()) {
                            this.selectionManager.clear();
                            try {
                                await this.comments.addComment(content, id);
                                this.loadAndRenderComments();
                            } catch (e) {
                                alert('Failed to post reply: ' + e.message);
                            }
                        }
                    }
                };
            });
        }
    }

    // ===================
    // Styles
    // ===================
    function injectStyles() {
        const style = document.createElement('style');
        style.textContent = `
            /* Auth Bar */
            #collab-auth-bar {
                position: fixed;
                top: 0;
                right: 0;
                left: 0;
                height: 48px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                z-index: 9999;
                display: flex;
                align-items: center;
                justify-content: flex-end;
                padding: 0 20px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }

            .md-header { top: 48px !important; }
            .md-tabs { top: 48px !important; }
            body { padding-top: 48px !important; }

            .collab-auth-content {
                display: flex;
                align-items: center;
                gap: 12px;
            }

            .collab-user-info {
                display: flex;
                align-items: center;
                gap: 8px;
            }

            .collab-avatar {
                width: 32px;
                height: 32px;
                border-radius: 50%;
                background: rgba(255,255,255,0.2);
                display: flex;
                align-items: center;
                justify-content: center;
                font-weight: 600;
            }

            .collab-avatar-small {
                width: 28px;
                height: 28px;
                border-radius: 50%;
                background: #667eea;
                color: white;
                display: flex;
                align-items: center;
                justify-content: center;
                font-size: 12px;
                font-weight: 600;
            }

            .collab-user-name { font-weight: 500; }

            .collab-role-badge {
                padding: 2px 8px;
                border-radius: 4px;
                font-size: 11px;
                font-weight: 600;
                text-transform: uppercase;
            }

            .collab-role-editor { background: #4caf50; color: white; }
            .collab-role-viewer { background: #2196f3; color: white; }

            .collab-no-access {
                color: #ffeb3b;
                font-size: 14px;
            }

            .collab-btn {
                padding: 8px 16px;
                border-radius: 6px;
                border: none;
                cursor: pointer;
                font-size: 14px;
                display: flex;
                align-items: center;
                gap: 6px;
                transition: all 0.2s;
            }

            .collab-btn-primary { background: white; color: #667eea; }
            .collab-btn-primary:hover { background: #f0f0f0; }
            .collab-btn-secondary { background: rgba(255,255,255,0.2); color: white; }
            .collab-btn-secondary:hover { background: rgba(255,255,255,0.3); }
            .collab-btn-full { width: 100%; justify-content: center; margin-top: 10px; }
            .collab-btn-small { padding: 6px 12px; font-size: 13px; }

            .collab-badge {
                background: #ff4757;
                color: white;
                padding: 2px 8px;
                border-radius: 10px;
                font-size: 12px;
            }

            /* Selection Toolbar - Professional floating toolbar */
            .collab-selection-toolbar {
                background: #1a1a2e;
                border-radius: 8px;
                box-shadow: 0 4px 20px rgba(0,0,0,0.25), 0 0 0 1px rgba(255,255,255,0.1);
                padding: 6px;
                opacity: 0;
                transform: translateX(-50%) translateY(10px);
                transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
                pointer-events: none;
            }

            .collab-selection-toolbar.collab-toolbar-visible {
                opacity: 1;
                transform: translateX(-50%) translateY(0);
                pointer-events: auto;
            }

            .collab-toolbar-content {
                display: flex;
                gap: 4px;
            }

            .collab-toolbar-btn {
                display: flex;
                align-items: center;
                gap: 6px;
                padding: 8px 14px;
                border: none;
                border-radius: 6px;
                background: transparent;
                color: #e0e0e0;
                font-size: 13px;
                font-weight: 500;
                cursor: pointer;
                transition: all 0.15s ease;
                white-space: nowrap;
            }

            .collab-toolbar-btn:hover {
                background: rgba(255,255,255,0.1);
                color: white;
            }

            .collab-toolbar-btn-primary {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }

            .collab-toolbar-btn-primary:hover {
                background: linear-gradient(135deg, #5a6fd6 0%, #6a4190 100%);
                transform: scale(1.02);
            }

            .collab-toolbar-btn svg {
                flex-shrink: 0;
            }

            .collab-toolbar-arrow {
                position: absolute;
                bottom: -6px;
                left: 50%;
                transform: translateX(-50%);
                width: 12px;
                height: 12px;
                background: #1a1a2e;
                border-radius: 2px;
                transform: translateX(-50%) rotate(45deg);
                box-shadow: 2px 2px 4px rgba(0,0,0,0.1);
            }

            .collab-toolbar-divider {
                width: 1px;
                background: rgba(255,255,255,0.2);
                margin: 4px 4px;
            }

            .collab-toolbar-btn-comment {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
            }

            .collab-toolbar-btn-comment:hover {
                background: linear-gradient(135deg, #5a6fd6 0%, #6a4190 100%);
            }

            .collab-toolbar-btn-highlight {
                background: linear-gradient(135deg, #fff59d 0%, #ffeb3b 100%);
                color: #5d4037;
            }

            .collab-toolbar-btn-highlight:hover {
                background: linear-gradient(135deg, #ffeb3b 0%, #fdd835 100%);
            }

            /* Color Picker */
            .collab-color-picker {
                padding: 8px;
                border-top: 1px solid rgba(255,255,255,0.1);
                margin-top: 6px;
            }

            .collab-color-label {
                font-size: 11px;
                color: #aaa;
                margin-bottom: 6px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            .collab-color-options {
                display: flex;
                gap: 6px;
                flex-wrap: wrap;
            }

            .collab-color-btn {
                width: 28px;
                height: 28px;
                border: 2px solid transparent;
                border-radius: 6px;
                cursor: pointer;
                transition: all 0.15s ease;
                box-shadow: 0 2px 4px rgba(0,0,0,0.2);
            }

            .collab-color-btn:hover {
                transform: scale(1.15);
                border-color: white;
                box-shadow: 0 4px 8px rgba(0,0,0,0.3);
            }

            .collab-selection-toolbar.collab-toolbar-expanded {
                padding-bottom: 8px;
            }

            .collab-selection-toolbar.collab-toolbar-expanded .collab-toolbar-arrow {
                display: none;
            }

            /* Persistent Highlights */
            .collab-highlight {
                transition: background-color 0.2s ease;
                border-radius: 2px;
            }

            .collab-highlight:hover {
                filter: brightness(0.95);
            }

            .collab-highlight-comment {
                border-bottom: 2px solid rgba(102, 126, 234, 0.5);
            }

            .collab-highlight-highlight {
                border-bottom: none;
            }

            /* Comment highlight animation when clicked */
            .collab-comment-highlight {
                animation: commentPulse 0.5s ease 2;
                background-color: rgba(102, 126, 234, 0.15) !important;
            }

            @keyframes commentPulse {
                0%, 100% { background-color: transparent; }
                50% { background-color: rgba(102, 126, 234, 0.2); }
            }

            /* Temporary highlight (preview) */
            .collab-temp-highlight {
                border-radius: 2px;
                padding: 1px 0;
            }

            /* Inline Comment Box - Modern card design */
            .collab-inline-comment-box {
                width: 360px;
                background: white;
                border-radius: 12px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.15), 0 0 0 1px rgba(0,0,0,0.05);
                opacity: 0;
                transform: translateY(-10px);
                transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
                overflow: hidden;
            }

            .collab-inline-comment-box.collab-inline-visible {
                opacity: 1;
                transform: translateY(0);
            }

            .collab-inline-header {
                display: flex;
                align-items: flex-start;
                justify-content: space-between;
                padding: 14px 16px;
                background: linear-gradient(135deg, #f8f9ff 0%, #f0f4ff 100%);
                border-bottom: 1px solid #e8ecf4;
            }

            .collab-inline-quote {
                display: flex;
                align-items: flex-start;
                gap: 8px;
                flex: 1;
                font-size: 13px;
                color: #5a67a0;
                font-style: italic;
                line-height: 1.5;
            }

            .collab-inline-quote svg {
                flex-shrink: 0;
                margin-top: 2px;
                opacity: 0.6;
            }

            .collab-inline-quote span {
                word-break: break-word;
            }

            .collab-inline-close {
                background: none;
                border: none;
                font-size: 20px;
                color: #999;
                cursor: pointer;
                padding: 0;
                line-height: 1;
                margin-left: 8px;
                transition: color 0.15s;
            }

            .collab-inline-close:hover {
                color: #333;
            }

            .collab-inline-body {
                padding: 16px;
            }

            .collab-inline-textarea {
                width: 100%;
                padding: 12px 14px;
                border: 2px solid #e8ecf4;
                border-radius: 8px;
                font-family: inherit;
                font-size: 14px;
                line-height: 1.5;
                resize: none;
                transition: all 0.2s ease;
                box-sizing: border-box;
            }

            .collab-inline-textarea:focus {
                outline: none;
                border-color: #667eea;
                box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.15);
            }

            .collab-inline-textarea.collab-inline-error {
                border-color: #ff4757;
                animation: shake 0.4s ease;
            }

            @keyframes shake {
                0%, 100% { transform: translateX(0); }
                25% { transform: translateX(-4px); }
                75% { transform: translateX(4px); }
            }

            .collab-inline-actions {
                display: flex;
                justify-content: flex-end;
                gap: 10px;
                margin-top: 12px;
            }

            .collab-inline-cancel {
                padding: 10px 18px;
                border: none;
                border-radius: 6px;
                background: #f5f5f5;
                color: #666;
                font-size: 14px;
                font-weight: 500;
                cursor: pointer;
                transition: all 0.15s ease;
            }

            .collab-inline-cancel:hover {
                background: #eee;
            }

            .collab-inline-submit {
                padding: 10px 20px;
                border: none;
                border-radius: 6px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                font-size: 14px;
                font-weight: 600;
                cursor: pointer;
                transition: all 0.15s ease;
                display: flex;
                align-items: center;
                gap: 8px;
            }

            .collab-inline-submit:hover:not(:disabled) {
                transform: translateY(-1px);
                box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
            }

            .collab-inline-submit:disabled {
                opacity: 0.7;
                cursor: not-allowed;
            }

            .collab-inline-submit-loading {
                display: flex;
                align-items: center;
                gap: 8px;
            }

            .collab-spinner {
                animation: spin 1s linear infinite;
            }

            @keyframes spin {
                from { transform: rotate(0deg); }
                to { transform: rotate(360deg); }
            }

            .collab-inline-error-message {
                background: #fff5f5;
                color: #c53030;
                padding: 8px 12px;
                border-radius: 6px;
                font-size: 13px;
                margin-bottom: 8px;
                animation: fadeIn 0.2s ease;
            }

            .collab-inline-success-message {
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 10px;
                padding: 24px;
                color: #38a169;
                font-weight: 500;
            }

            .collab-inline-success-message svg {
                color: #38a169;
            }

            .collab-inline-comment-box.collab-inline-success {
                background: #f0fff4;
            }

            @keyframes fadeIn {
                from { opacity: 0; }
                to { opacity: 1; }
            }

            /* Temporary highlight for selected text */
            .collab-temp-highlight {
                background: linear-gradient(120deg, rgba(255, 213, 79, 0.4) 0%, rgba(255, 193, 7, 0.4) 100%);
                border-radius: 2px;
                padding: 1px 0;
            }

            /* Legacy Selection Popup (kept for compatibility) */
            .collab-selection-popup {
                position: absolute;
                background: #333;
                padding: 8px;
                border-radius: 6px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.2);
                z-index: 10001;
                transform: translateY(-100%) translateX(-50%);
                margin-top: -10px;
            }

            /* Selection Preview */
            .collab-selection-preview {
                background: #f8f9fa;
                padding: 12px;
                margin: 0 16px;
                border-radius: 6px;
                border-left: 3px solid #667eea;
            }

            .collab-selection-preview blockquote {
                margin: 8px 0 0 0;
                font-style: italic;
                color: #666;
            }

            /* Comment Selection Quote */
            .collab-comment-selection {
                background: #fff3e0;
                padding: 8px 12px;
                margin: 8px 0;
                border-left: 3px solid #ff9800;
                border-radius: 4px;
            }

            .collab-comment-selection blockquote {
                margin: 0;
                font-style: italic;
                color: #e65100;
                font-size: 13px;
            }

            /* Comments Panel */
            #collab-comments-panel {
                position: fixed;
                right: 0;
                top: 48px;
                bottom: 0;
                width: 380px;
                background: white;
                box-shadow: -4px 0 20px rgba(0,0,0,0.1);
                z-index: 9998;
                display: flex;
                flex-direction: column;
                transition: transform 0.3s ease;
            }

            #collab-comments-panel.collab-panel-hidden { transform: translateX(100%); }

            .collab-panel-header {
                padding: 16px 20px;
                border-bottom: 1px solid #eee;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }

            .collab-panel-header h3 { margin: 0; font-size: 18px; color: #333; }

            .collab-close-btn {
                background: none;
                border: none;
                font-size: 24px;
                cursor: pointer;
                color: #999;
            }

            .collab-close-btn:hover { color: #333; }

            .collab-comments-list { flex: 1; overflow-y: auto; padding: 16px; }

            .collab-comment {
                background: #f8f9fa;
                border-radius: 8px;
                padding: 12px;
                margin-bottom: 12px;
            }

            .collab-comment-resolved {
                opacity: 0.7;
                border-left: 3px solid #4caf50;
            }

            .collab-comment-header {
                display: flex;
                align-items: center;
                gap: 8px;
                margin-bottom: 8px;
            }

            .collab-comment-author { font-weight: 600; color: #333; }
            .collab-comment-date { font-size: 12px; color: #999; }

            .collab-tag {
                font-size: 10px;
                padding: 2px 6px;
                border-radius: 4px;
                background: #667eea;
                color: white;
            }

            .collab-tag-resolved { background: #4caf50; }

            .collab-comment-content { color: #555; line-height: 1.5; font-size: 14px; }

            .collab-comment-actions { display: flex; gap: 12px; margin-top: 8px; }

            .collab-action-btn {
                background: none;
                border: none;
                color: #667eea;
                cursor: pointer;
                font-size: 13px;
                padding: 4px 8px;
                border-radius: 4px;
            }

            .collab-action-btn:hover { background: #f0f0f0; }

            .collab-replies {
                margin-left: 20px;
                margin-top: 12px;
                padding-left: 12px;
                border-left: 2px solid #ddd;
            }

            .collab-comment-form { padding: 16px; border-top: 1px solid #eee; }

            .collab-comment-form textarea {
                width: 100%;
                padding: 12px;
                border: 1px solid #ddd;
                border-radius: 8px;
                resize: none;
                font-family: inherit;
                box-sizing: border-box;
            }

            .collab-comment-form textarea:focus { outline: none; border-color: #667eea; }

            .collab-form-actions { margin-top: 10px; }

            .collab-no-comments, .collab-loading, .collab-login-prompt {
                text-align: center;
                color: #999;
                padding: 40px 20px;
            }

            /* Editor Styles */
            .collab-btn-edit {
                position: absolute;
                right: 20px;
                top: 10px;
                z-index: 100;
            }

            .collab-btn-save { background: #4caf50 !important; color: white !important; }

            .collab-btn-cancel {
                background: #f44336;
                color: white;
                margin-left: 8px;
                position: absolute;
                right: 140px;
                top: 10px;
                z-index: 100;
            }

            .collab-editing {
                border: 2px dashed #667eea !important;
                padding: 20px !important;
                min-height: 200px;
            }

            .collab-toolbar {
                background: #f5f5f5;
                border: 1px solid #ddd;
                border-radius: 6px;
                padding: 8px;
                margin-bottom: 12px;
                display: flex;
                gap: 4px;
                flex-wrap: wrap;
            }

            .collab-toolbar button {
                background: white;
                border: 1px solid #ddd;
                border-radius: 4px;
                padding: 6px 10px;
                cursor: pointer;
                font-size: 14px;
            }

            .collab-toolbar button:hover { background: #e0e0e0; }

            /* Notification */
            .collab-notification {
                position: fixed;
                bottom: 20px;
                right: 20px;
                padding: 12px 24px;
                border-radius: 6px;
                color: white;
                font-weight: 500;
                z-index: 10002;
                animation: slideIn 0.3s ease;
            }

            .collab-notification-success { background: #4caf50; }
            .collab-notification-error { background: #f44336; }

            @keyframes slideIn {
                from { transform: translateX(100%); opacity: 0; }
                to { transform: translateX(0); opacity: 1; }
            }

            /* Modal */
            .collab-modal {
                position: fixed;
                top: 0;
                left: 0;
                right: 0;
                bottom: 0;
                background: rgba(0,0,0,0.5);
                display: flex;
                align-items: center;
                justify-content: center;
                z-index: 10000;
            }

            .collab-modal-content {
                background: white;
                border-radius: 12px;
                width: 90%;
                max-width: 400px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            }

            .collab-modal-header {
                padding: 16px 20px;
                border-bottom: 1px solid #eee;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }

            .collab-modal-header h3 { margin: 0; color: #333; }

            .collab-modal-body { padding: 20px; }

            .collab-modal-body input {
                width: 100%;
                padding: 12px;
                border: 1px solid #ddd;
                border-radius: 8px;
                font-size: 14px;
                margin-top: 8px;
                box-sizing: border-box;
            }

            .collab-modal-body input:focus { outline: none; border-color: #667eea; }

            .collab-form-group { margin-bottom: 16px; }
            .collab-form-group label { font-weight: 600; color: #333; font-size: 14px; }

            .collab-error {
                color: #ff4757;
                background: #ffe0e0;
                padding: 10px;
                border-radius: 6px;
                margin-top: 12px;
                font-size: 14px;
            }

            /* Enhanced Login Modal */
            .collab-login-modal-content {
                max-width: 420px;
            }

            .collab-login-description {
                color: #666;
                font-size: 14px;
                margin-bottom: 20px;
                line-height: 1.5;
            }

            .collab-login-error {
                display: flex;
                align-items: flex-start;
                gap: 10px;
                padding: 12px 14px;
                border-radius: 8px;
                margin-bottom: 16px;
                font-size: 14px;
                line-height: 1.4;
            }

            .collab-login-error-error,
            .collab-login-error-auth {
                background: linear-gradient(135deg, #fff5f5 0%, #ffe8e8 100%);
                border: 1px solid #feb2b2;
                color: #c53030;
            }

            .collab-login-error-validation {
                background: linear-gradient(135deg, #fffbeb 0%, #fef3c7 100%);
                border: 1px solid #f6e05e;
                color: #b7791f;
            }

            .collab-login-error-locked {
                background: linear-gradient(135deg, #fef5ff 0%, #f3e8ff 100%);
                border: 1px solid #d6bcfa;
                color: #805ad5;
            }

            .collab-login-error-network {
                background: linear-gradient(135deg, #f0f9ff 0%, #e0f2fe 100%);
                border: 1px solid #7dd3fc;
                color: #0369a1;
            }

            .collab-error-icon {
                flex-shrink: 0;
                margin-top: 1px;
            }

            .collab-error-text {
                flex: 1;
            }

            .collab-shake {
                animation: shake 0.4s ease;
            }

            .collab-password-wrapper {
                position: relative;
            }

            .collab-password-wrapper input {
                padding-right: 44px;
            }

            .collab-password-toggle {
                position: absolute;
                right: 8px;
                top: 50%;
                transform: translateY(-50%);
                background: none;
                border: none;
                padding: 6px;
                cursor: pointer;
                color: #999;
                transition: color 0.15s;
                display: flex;
                align-items: center;
                justify-content: center;
            }

            .collab-password-toggle:hover {
                color: #666;
            }

            .collab-login-btn {
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 8px;
                padding: 14px 20px;
                font-size: 15px;
                font-weight: 600;
                transition: all 0.2s ease;
            }

            .collab-login-btn:hover:not(:disabled) {
                transform: translateY(-1px);
                box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
            }

            .collab-login-btn:disabled {
                opacity: 0.7;
                cursor: not-allowed;
                transform: none;
            }

            .collab-login-btn-loading {
                display: flex;
                align-items: center;
                gap: 8px;
            }

            .collab-login-success {
                background: linear-gradient(135deg, #48bb78 0%, #38a169 100%) !important;
            }

            .collab-login-help {
                text-align: center;
                color: #999;
                font-size: 13px;
                margin-top: 16px;
                margin-bottom: 0;
            }

            /* Responsive */
            @media (max-width: 768px) {
                #collab-comments-panel { width: 100%; }
                .collab-user-name { display: none; }
            }
        `;
        document.head.appendChild(style);
    }

    // ===================
    // Initialize
    // ===================
    async function init() {
        const auth = new AuthManager();
        const selectionManager = new TextSelectionManager();
        const comments = new CommentsManager(auth, selectionManager);
        const editor = new InlineEditor(auth);
        const ui = new CollaborationUI(auth, comments, editor, selectionManager);

        await ui.init();
    }

    // Run when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
