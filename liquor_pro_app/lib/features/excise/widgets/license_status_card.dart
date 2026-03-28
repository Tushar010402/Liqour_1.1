import 'package:flutter/material.dart';

class LicenseStatusCard extends StatelessWidget {
  final int totalLicenses;
  final int activeLicenses;
  final int expiringLicenses;
  final VoidCallback? onTap;

  const LicenseStatusCard({
    super.key,
    required this.totalLicenses,
    required this.activeLicenses,
    required this.expiringLicenses,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.verified_user,
                      color: Colors.blue[700],
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  if (expiringLicenses > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$expiringLicenses',
                        style: TextStyle(
                          color: Colors.orange[900],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                '$activeLicenses',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Active Licenses',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface,
                ),
              ),
              if (expiringLicenses > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$expiringLicenses expiring soon',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
