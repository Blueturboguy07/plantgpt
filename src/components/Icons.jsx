import React from "react";

const I = ({ size = 18, children, ...rest }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.7"
    strokeLinecap="round"
    strokeLinejoin="round"
    {...rest}
  >
    {children}
  </svg>
);

export const PanelIcon = (p) => (
  <I {...p}>
    <rect x="3" y="4" width="18" height="16" rx="3" />
    <line x1="9.5" y1="4" x2="9.5" y2="20" />
  </I>
);
export const PencilIcon = (p) => (
  <I {...p}>
    <path d="M12 20h9" />
    <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
  </I>
);
export const SearchIcon = (p) => (
  <I {...p}>
    <circle cx="11" cy="11" r="7" />
    <line x1="21" y1="21" x2="16.2" y2="16.2" />
  </I>
);
export const FolderPlusIcon = (p) => (
  <I {...p}>
    <path d="M4 6a2 2 0 0 1 2-2h4l2 2h6a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z" />
    <line x1="12" y1="11" x2="12" y2="15" />
    <line x1="10" y1="13" x2="14" y2="13" />
  </I>
);
export const FolderIcon = (p) => (
  <I {...p}>
    <path d="M4 6a2 2 0 0 1 2-2h4l2 2h6a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z" />
  </I>
);
export const PlusIcon = (p) => (
  <I {...p}>
    <line x1="12" y1="5" x2="12" y2="19" />
    <line x1="5" y1="12" x2="19" y2="12" />
  </I>
);
export const MicIcon = (p) => (
  <I {...p}>
    <rect x="9" y="3" width="6" height="11" rx="3" />
    <path d="M5 11a7 7 0 0 0 14 0" />
    <line x1="12" y1="18" x2="12" y2="21" />
  </I>
);
export const ArrowUpIcon = (p) => (
  <I {...p} strokeWidth="2.1">
    <line x1="12" y1="19" x2="12" y2="5" />
    <polyline points="6 11 12 5 18 11" />
  </I>
);
export const ArrowDownIcon = (p) => (
  <I {...p} strokeWidth="2">
    <line x1="12" y1="5" x2="12" y2="19" />
    <polyline points="6 13 12 19 18 13" />
  </I>
);
export const CopyIcon = (p) => (
  <I {...p}>
    <rect x="9" y="9" width="11" height="11" rx="2.5" />
    <path d="M5 15H4.5A1.5 1.5 0 0 1 3 13.5v-9A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5" />
  </I>
);
export const ThumbUpIcon = (p) => (
  <I {...p}>
    <path d="M7 10v11" />
    <path d="M15 5.9 14 10h5.2a2 2 0 0 1 1.9 2.6l-1.9 6A2 2 0 0 1 17.3 20H7V10l4-7a2.4 2.4 0 0 1 4 2.9Z" />
  </I>
);
export const ThumbDownIcon = (p) => (
  <I {...p}>
    <path d="M17 14V3" />
    <path d="M9 18.1 10 14H4.8a2 2 0 0 1-1.9-2.6l1.9-6A2 2 0 0 1 6.7 4H17v10l-4 7a2.4 2.4 0 0 1-4-2.9Z" />
  </I>
);
export const ShareIcon = (p) => (
  <I {...p}>
    <path d="M12 3v12" />
    <polyline points="7 8 12 3 17 8" />
    <path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" />
  </I>
);
export const RefreshIcon = (p) => (
  <I {...p}>
    <path d="M21 12a9 9 0 1 1-2.6-6.3" />
    <polyline points="21 3 21 9 15 9" />
  </I>
);
export const XIcon = (p) => (
  <I {...p}>
    <line x1="5" y1="5" x2="19" y2="19" />
    <line x1="19" y1="5" x2="5" y2="19" />
  </I>
);
export const GlobeIcon = (p) => (
  <I {...p}>
    <circle cx="12" cy="12" r="9" />
    <line x1="3" y1="12" x2="21" y2="12" />
    <path d="M12 3a14.5 14.5 0 0 1 0 18a14.5 14.5 0 0 1 0-18" />
  </I>
);
export const PaperclipIcon = (p) => (
  <I {...p}>
    <path d="m21 11.5-8.5 8.5a5.5 5.5 0 0 1-7.8-7.8L13 3.9a3.7 3.7 0 0 1 5.2 5.2L10 17.3a1.8 1.8 0 0 1-2.6-2.6L15 7.1" />
  </I>
);
export const BookIcon = (p) => (
  <I {...p}>
    <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20V2H6.5A2.5 2.5 0 0 0 4 4.5Z" />
    <path d="M4 19.5A2.5 2.5 0 0 0 6.5 22H20v-5" />
  </I>
);
export const ImageIcon = (p) => (
  <I {...p}>
    <rect x="3" y="3" width="18" height="18" rx="3" />
    <circle cx="8.5" cy="8.5" r="1.5" fill="currentColor" stroke="none" />
    <path d="m21 15-4.5-4.5L7 20" />
  </I>
);
export const ChevronRightIcon = (p) => (
  <I {...p}>
    <polyline points="9 6 15 12 9 18" />
  </I>
);
export const ChevronLeftIcon = (p) => (
  <I {...p}>
    <polyline points="15 6 9 12 15 18" />
  </I>
);
export const ExtIcon = (p) => (
  <I {...p}>
    <line x1="7" y1="17" x2="17" y2="7" />
    <polyline points="9 7 17 7 17 15" />
  </I>
);
export const CheckIcon = (p) => (
  <I {...p}>
    <polyline points="4.5 12.5 9.5 17.5 19.5 6.5" />
  </I>
);
export const TrashIcon = (p) => (
  <I {...p}>
    <path d="M4 7h16" />
    <path d="M10 11v6M14 11v6" />
    <path d="M6 7l1 13a1.8 1.8 0 0 0 1.8 1.6h6.4A1.8 1.8 0 0 0 17 20l1-13" />
    <path d="M9 7V4.8A1.8 1.8 0 0 1 10.8 3h2.4A1.8 1.8 0 0 1 15 4.8V7" />
  </I>
);
export const DotsIcon = (p) => (
  <I {...p}>
    <circle cx="5" cy="12" r="1.4" fill="currentColor" stroke="none" />
    <circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none" />
    <circle cx="19" cy="12" r="1.4" fill="currentColor" stroke="none" />
  </I>
);
export const MapIcon = (p) => (
  <I {...p}>
    <path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2Z" />
    <line x1="9" y1="4" x2="9" y2="18" />
    <line x1="15" y1="6" x2="15" y2="20" />
  </I>
);
export const StopIcon = (p) => (
  <I {...p}>
    <rect x="7" y="7" width="10" height="10" rx="2" fill="currentColor" stroke="none" />
  </I>
);
export const DiscordIcon = ({ size = 18, ...rest }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" {...rest}>
    <path d="M19.3 5.3A16.9 16.9 0 0 0 15.1 4l-.2.4a15.6 15.6 0 0 0-5.8 0L8.9 4a16.9 16.9 0 0 0-4.2 1.3A17.6 17.6 0 0 0 1.7 17a17 17 0 0 0 5.2 2.6l.7-1.2a11 11 0 0 1-1.7-.8l.4-.3a12.1 12.1 0 0 0 10.4 0l.4.3c-.5.3-1.1.6-1.7.8l.7 1.2A17 17 0 0 0 22.3 17a17.6 17.6 0 0 0-3-11.7ZM8.7 14.8c-1 0-1.8-.9-1.8-2s.8-2 1.8-2 1.9.9 1.8 2c0 1.1-.8 2-1.8 2Zm6.6 0c-1 0-1.8-.9-1.8-2s.8-2 1.8-2 1.9.9 1.8 2c0 1.1-.8 2-1.8 2Z" />
  </svg>
);
