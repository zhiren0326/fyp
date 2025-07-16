class OnBoarding {
  final String title;
  final String image;

  OnBoarding({
    required this.title,
    required this.image,
  });
}

List<OnBoarding> onboardingContents = [
  OnBoarding(
    image: 'assets/images/Onboard/onboarding_image_1.png',
    title: 'Welcome to\n Tazz App',
  ),
  OnBoarding(
    title: 'Find Your\n Favorite Job and Task !',
    image: 'assets/images/Onboard/onboarding_image_5.png',
  ),
  OnBoarding(
    title: 'Keep track of your progress',
    image: 'assets/images/Onboard/onboarding_image_3.png',
  ),
  OnBoarding(
    title: 'Make Your\n Career Choice !',
    image: 'assets/images/Onboard/onboarding_image_6.png',
  ),
  OnBoarding(
    title: 'Join a supportive community',
    image: 'assets/images/Onboard/onboarding_image_4.png',
  ),
];
