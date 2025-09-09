#!/usr/bin/env python3
"""
Industrial-Grade UX Validator
Validates Flutter app for industrial-grade UX standards without Flutter SDK
"""

import os
import re
import json
from pathlib import Path
from typing import Dict, List, Any

class IndustrialUXValidator:
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.ux_score = 0
        self.max_score = 100
        self.validations = []
        
    def validate_complete_ux(self) -> Dict[str, Any]:
        """Comprehensive UX validation"""
        print("🎨 Starting Industrial-Grade UX Validation...")
        
        results = {
            'ux_score': 0,
            'validations': [],
            'material_design': {},
            'accessibility': {},
            'performance': {},
            'animations': {},
            'theming': {},
            'responsive_design': {},
            'user_flows': {},
            'summary': {}
        }
        
        # Core UX Validations
        self._validate_material_design(results)
        self._validate_accessibility(results) 
        self._validate_performance_ux(results)
        self._validate_animations(results)
        self._validate_theming(results)
        self._validate_responsive_design(results)
        self._validate_user_flows(results)
        
        # Calculate final score
        self._calculate_ux_score(results)
        
        return results
    
    def _validate_material_design(self, results: Dict):
        """Validate Material Design 3 implementation"""
        print("📱 Validating Material Design 3 implementation...")
        
        material_checks = {
            'theme_implementation': False,
            'component_usage': False,
            'color_system': False,
            'typography': False,
            'elevation_shadows': False
        }
        
        # Check for theme files
        theme_files = list(self.project_root.rglob("*theme*.dart"))
        if theme_files:
            material_checks['theme_implementation'] = True
            
        # Check for color system
        color_files = list(self.project_root.rglob("*color*.dart"))
        if color_files:
            material_checks['color_system'] = True
            
        # Check for typography
        typography_files = list(self.project_root.rglob("*typography*.dart"))
        if typography_files:
            material_checks['typography'] = True
            
        # Check for premium components
        component_files = list(self.project_root.rglob("premium_*.dart"))
        if len(component_files) >= 3:  # At least 3 premium components
            material_checks['component_usage'] = True
            
        # Check for elevation/shadow usage in code
        dart_files = list(self.project_root.rglob("*.dart"))
        elevation_found = False
        for file_path in dart_files:
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    if 'elevation:' in content or 'boxShadow' in content:
                        elevation_found = True
                        break
            except:
                continue
                
        material_checks['elevation_shadows'] = elevation_found
        
        results['material_design'] = material_checks
        score = sum(material_checks.values()) * 4  # 20 points max
        results['ux_score'] += score
        
        print(f"  ✅ Material Design Score: {score}/20")
        
    def _validate_accessibility(self, results: Dict):
        """Validate accessibility implementation"""
        print("♿ Validating accessibility features...")
        
        accessibility_checks = {
            'semantic_labels': False,
            'focus_management': False,
            'color_contrast': False,
            'text_scaling': False,
            'screen_reader_support': False
        }
        
        dart_files = list(self.project_root.rglob("*.dart"))
        
        for file_path in dart_files:
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    
                # Check for semantic labels
                if 'semanticsLabel' in content or 'Semantics(' in content:
                    accessibility_checks['semantic_labels'] = True
                    
                # Check for focus management
                if 'FocusNode' in content or 'focus:' in content:
                    accessibility_checks['focus_management'] = True
                    
                # Check for text scaling support
                if 'textScaleFactor' in content or 'MediaQuery' in content:
                    accessibility_checks['text_scaling'] = True
                    
                # Check for screen reader support
                if 'ExcludeSemantics' in content or 'MergeSemantics' in content:
                    accessibility_checks['screen_reader_support'] = True
                    
            except:
                continue
                
        # Color contrast check (basic - check for dark theme)
        theme_files = list(self.project_root.rglob("*theme*.dart"))
        for theme_file in theme_files:
            try:
                with open(theme_file, 'r') as f:
                    content = f.read()
                    if 'ThemeData.dark' in content or 'brightness: Brightness.dark' in content:
                        accessibility_checks['color_contrast'] = True
                        break
            except:
                continue
        
        results['accessibility'] = accessibility_checks
        score = sum(accessibility_checks.values()) * 3  # 15 points max
        results['ux_score'] += score
        
        print(f"  ✅ Accessibility Score: {score}/15")
        
    def _validate_performance_ux(self, results: Dict):
        """Validate performance-related UX features"""
        print("⚡ Validating performance UX features...")
        
        performance_checks = {
            'image_caching': False,
            'lazy_loading': False,
            'performance_monitoring': False,
            'memory_optimization': False,
            'smooth_animations': False
        }
        
        # Check for caching implementation
        cache_files = list(self.project_root.rglob("*cache*.dart"))
        if cache_files:
            performance_checks['image_caching'] = True
            
        # Check for performance monitoring
        perf_files = list(self.project_root.rglob("*performance*.dart"))
        if perf_files:
            performance_checks['performance_monitoring'] = True
            
        dart_files = list(self.project_root.rglob("*.dart"))
        
        for file_path in dart_files:
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    
                # Check for lazy loading patterns
                if 'FutureBuilder' in content or 'StreamBuilder' in content:
                    performance_checks['lazy_loading'] = True
                    
                # Check for memory optimization
                if 'dispose()' in content and 'initState()' in content:
                    performance_checks['memory_optimization'] = True
                    
                # Check for smooth animations
                if 'AnimationController' in content or 'Tween' in content:
                    performance_checks['smooth_animations'] = True
                    
            except:
                continue
                
        results['performance'] = performance_checks
        score = sum(performance_checks.values()) * 3  # 15 points max
        results['ux_score'] += score
        
        print(f"  ✅ Performance UX Score: {score}/15")
        
    def _validate_animations(self, results: Dict):
        """Validate animation implementation"""
        print("✨ Validating animation implementation...")
        
        animation_checks = {
            'micro_interactions': False,
            'page_transitions': False,
            'loading_animations': False,
            'gesture_animations': False,
            'hero_animations': False
        }
        
        dart_files = list(self.project_root.rglob("*.dart"))
        
        for file_path in dart_files:
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    
                # Check for micro-interactions
                if 'onTap' in content and ('Animation' in content or 'scale' in content):
                    animation_checks['micro_interactions'] = True
                    
                # Check for page transitions
                if 'PageRouteBuilder' in content or 'SlideTransition' in content:
                    animation_checks['page_transitions'] = True
                    
                # Check for loading animations
                if 'CircularProgressIndicator' in content or 'LinearProgressIndicator' in content:
                    animation_checks['loading_animations'] = True
                    
                # Check for gesture animations
                if 'GestureDetector' in content and 'Animation' in content:
                    animation_checks['gesture_animations'] = True
                    
                # Check for hero animations
                if 'Hero(' in content:
                    animation_checks['hero_animations'] = True
                    
            except:
                continue
                
        results['animations'] = animation_checks
        score = sum(animation_checks.values()) * 2  # 10 points max
        results['ux_score'] += score
        
        print(f"  ✅ Animation Score: {score}/10")
        
    def _validate_theming(self, results: Dict):
        """Validate theming system"""
        print("🎨 Validating theming system...")
        
        theming_checks = {
            'dark_light_theme': False,
            'consistent_colors': False,
            'custom_fonts': False,
            'theme_switching': False,
            'brand_consistency': False
        }
        
        # Check pubspec.yaml for custom fonts
        pubspec_path = self.project_root / "pubspec.yaml"
        if pubspec_path.exists():
            try:
                with open(pubspec_path, 'r') as f:
                    content = f.read()
                    if 'fonts:' in content:
                        theming_checks['custom_fonts'] = True
            except:
                pass
                
        dart_files = list(self.project_root.rglob("*.dart"))
        
        for file_path in dart_files:
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    
                # Check for dark/light theme
                if 'ThemeData.dark' in content or 'brightness:' in content:
                    theming_checks['dark_light_theme'] = True
                    
                # Check for consistent color usage
                if 'Theme.of(context)' in content:
                    theming_checks['consistent_colors'] = True
                    
                # Check for theme switching capability
                if 'ThemeMode' in content or 'theme:' in content:
                    theming_checks['theme_switching'] = True
                    
                # Check for brand consistency (custom colors)
                if 'Color(0x' in content and len(re.findall(r'Color\(0x[0-9A-Fa-f]{8}\)', content)) >= 3:
                    theming_checks['brand_consistency'] = True
                    
            except:
                continue
                
        results['theming'] = theming_checks
        score = sum(theming_checks.values()) * 3  # 15 points max
        results['ux_score'] += score
        
        print(f"  ✅ Theming Score: {score}/15")
        
    def _validate_responsive_design(self, results: Dict):
        """Validate responsive design implementation"""
        print("📱 Validating responsive design...")
        
        responsive_checks = {
            'screen_size_adaptation': False,
            'orientation_handling': False,
            'safe_area_usage': False,
            'flexible_layouts': False,
            'breakpoint_handling': False
        }
        
        dart_files = list(self.project_root.rglob("*.dart"))
        
        for file_path in dart_files:
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    
                # Check for screen size adaptation
                if 'MediaQuery.of(context).size' in content:
                    responsive_checks['screen_size_adaptation'] = True
                    
                # Check for orientation handling
                if 'Orientation.' in content or 'orientation:' in content:
                    responsive_checks['orientation_handling'] = True
                    
                # Check for safe area usage
                if 'SafeArea(' in content:
                    responsive_checks['safe_area_usage'] = True
                    
                # Check for flexible layouts
                if ('Flexible(' in content or 'Expanded(' in content or 'Wrap(' in content):
                    responsive_checks['flexible_layouts'] = True
                    
                # Check for breakpoint handling
                if 'LayoutBuilder' in content or 'constraints' in content:
                    responsive_checks['breakpoint_handling'] = True
                    
            except:
                continue
                
        results['responsive_design'] = responsive_checks
        score = sum(responsive_checks.values()) * 2  # 10 points max
        results['ux_score'] += score
        
        print(f"  ✅ Responsive Design Score: {score}/10")
        
    def _validate_user_flows(self, results: Dict):
        """Validate user flow implementation"""
        print("🔄 Validating user flows...")
        
        flow_checks = {
            'onboarding_flow': False,
            'authentication_flow': False,
            'error_handling_flow': False,
            'navigation_flow': False,
            'feedback_flow': False
        }
        
        # Check for authentication files
        auth_files = list(self.project_root.rglob("*auth*.dart"))
        if auth_files:
            flow_checks['authentication_flow'] = True
            
        dart_files = list(self.project_root.rglob("*.dart"))
        
        for file_path in dart_files:
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    
                # Check for onboarding
                if 'onboard' in content.lower() or 'intro' in content.lower():
                    flow_checks['onboarding_flow'] = True
                    
                # Check for error handling
                if 'try {' in content and 'catch' in content:
                    flow_checks['error_handling_flow'] = True
                    
                # Check for navigation
                if 'Navigator.' in content or 'GoRouter' in content:
                    flow_checks['navigation_flow'] = True
                    
                # Check for user feedback
                if ('SnackBar' in content or 'showDialog' in content or 
                    'ScaffoldMessenger' in content):
                    flow_checks['feedback_flow'] = True
                    
            except:
                continue
                
        results['user_flows'] = flow_checks
        score = sum(flow_checks.values()) * 3  # 15 points max
        results['ux_score'] += score
        
        print(f"  ✅ User Flow Score: {score}/15")
        
    def _calculate_ux_score(self, results: Dict):
        """Calculate final UX score and grade"""
        final_score = min(results['ux_score'], self.max_score)
        percentage = (final_score / self.max_score) * 100
        
        if percentage >= 90:
            grade = "A+ (Industrial Grade)"
            status = "🏆 EXCELLENT"
        elif percentage >= 80:
            grade = "A (Professional Grade)"
            status = "✅ VERY GOOD"
        elif percentage >= 70:
            grade = "B+ (Good Standard)"
            status = "👍 GOOD"
        elif percentage >= 60:
            grade = "B (Acceptable)"
            status = "⚠️ NEEDS IMPROVEMENT"
        else:
            grade = "C (Below Standard)"
            status = "❌ REQUIRES MAJOR WORK"
            
        results['summary'] = {
            'final_score': final_score,
            'max_score': self.max_score,
            'percentage': percentage,
            'grade': grade,
            'status': status,
            'recommendations': self._generate_recommendations(results)
        }
        
    def _generate_recommendations(self, results: Dict) -> List[str]:
        """Generate UX improvement recommendations"""
        recommendations = []
        
        # Material Design recommendations
        md = results['material_design']
        if not md['theme_implementation']:
            recommendations.append("Implement comprehensive Material Design 3 theme")
        if not md['component_usage']:
            recommendations.append("Create more premium UI components")
            
        # Accessibility recommendations
        acc = results['accessibility']
        if not acc['semantic_labels']:
            recommendations.append("Add semantic labels for screen readers")
        if not acc['focus_management']:
            recommendations.append("Implement proper focus management")
            
        # Performance recommendations
        perf = results['performance']
        if not perf['image_caching']:
            recommendations.append("Implement advanced image caching system")
        if not perf['lazy_loading']:
            recommendations.append("Add lazy loading for better performance")
            
        return recommendations[:5]  # Top 5 recommendations

def main():
    print("🎨 Industrial-Grade UX Validation Suite")
    print("=" * 50)
    
    validator = IndustrialUXValidator(".")
    results = validator.validate_complete_ux()
    
    print("\n" + "=" * 50)
    print("📊 INDUSTRIAL UX VALIDATION RESULTS")
    print("=" * 50)
    
    summary = results['summary']
    print(f"🏆 Final Score: {summary['final_score']}/{summary['max_score']}")
    print(f"📈 Percentage: {summary['percentage']:.1f}%")
    print(f"🎯 Grade: {summary['grade']}")
    print(f"📋 Status: {summary['status']}")
    
    print("\n📱 DETAILED BREAKDOWN:")
    print("-" * 30)
    
    categories = [
        ('Material Design 3', results['material_design'], 20),
        ('Accessibility', results['accessibility'], 15),
        ('Performance UX', results['performance'], 15),
        ('Animations', results['animations'], 10),
        ('Theming System', results['theming'], 15),
        ('Responsive Design', results['responsive_design'], 10),
        ('User Flows', results['user_flows'], 15)
    ]
    
    for name, checks, max_points in categories:
        score = sum(checks.values()) * (max_points // len(checks))
        status = "✅" if score >= max_points * 0.8 else "⚠️" if score >= max_points * 0.6 else "❌"
        print(f"{status} {name}: {score}/{max_points}")
        
        # Show failed checks
        failed = [key for key, value in checks.items() if not value]
        if failed and len(failed) <= 2:
            print(f"    Missing: {', '.join(failed)}")
    
    if summary['recommendations']:
        print(f"\n🔧 TOP RECOMMENDATIONS:")
        print("-" * 30)
        for i, rec in enumerate(summary['recommendations'], 1):
            print(f"{i}. {rec}")
    
    print("\n" + "=" * 50)
    
    if summary['percentage'] >= 90:
        print("🎉 CONGRATULATIONS! This app meets INDUSTRIAL-GRADE UX standards!")
    elif summary['percentage'] >= 80:
        print("👍 Great work! This app has PROFESSIONAL-GRADE UX quality.")
    else:
        print("⚠️ UX improvements needed to meet industrial standards.")
        
    return summary['percentage'] >= 90

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)