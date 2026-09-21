import { OnexaBrandLockup } from "@/components/brand/onexa-brand";

type Props = {
  language: "en" | "ar";
  compact?: boolean;
};

export function BrandLogo({ language, compact = false }: Props) {
  return <OnexaBrandLockup language={language} compact={compact} />;
}
