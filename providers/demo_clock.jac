"""Rebase fictional observations only; raw fixtures remain reproducible."""
import from datetime { timedelta }
import from app_settings { instant }
def rebase_fixture(data: any, now: any = '') -> dict {
    if not now {
        return data;
    }
    anchor = instant((instant(now).date().isoformat() + 'T00:00:00'));
    original = instant(data['observed_at']);
    for offer in data['offers'] {
        observed = instant(offer.get('observed_at', data['observed_at']));
        expires = instant(offer.get('valid_until', data['valid_until']));
        if ((expires <= observed) or (observed > original)) {
            raise ValueError('Invalid mock observation interval');
        }
        shifted = anchor + (observed - original);
        offer['observed_at'] = shifted.isoformat(timespec='seconds');
        offer['valid_until'] = (shifted + (expires - observed)).isoformat(
            timespec='seconds'
        );
    }
    return data;
}
