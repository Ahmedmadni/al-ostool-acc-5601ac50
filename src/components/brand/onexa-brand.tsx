import type { ImgHTMLAttributes } from "react";

type BrandMarkProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src" | "alt"> & {
  title?: string;
};

type BrandLockupProps = {
  className?: string;
  markClassName?: string;
  language?: "ar" | "en";
  compact?: boolean;
  inverse?: boolean;
  showDescriptor?: boolean;
};

/**
 * Canonical ONEXA identity. The approved PNG is the sole visual source.
 * Do not redraw, recolor, crop, separate, or reconstruct its elements.
 */
export function OnexaBrandMark({ className, title = "ONEXA ERP", ...props }: BrandMarkProps) {
  return <img src="/onexa-logo-transparent.png" className={className} alt={title} {...props} />;
}

export function OnexaBrandLockup({
  className = "",
  markClassName = "",
  compact = false,
}: BrandLockupProps) {
  return (
    <span className={`inline-flex min-w-0 items-center ${className}`.trim()}>
      <OnexaBrandMark
        title="ONEXA ERP SYSTEM"
        className={`${compact ? "h-16 w-16 sm:h-20 sm:w-20" : "h-20 w-20"} shrink-0 object-contain ${markClassName}`.trim()}
      />
    </span>
  );
}
