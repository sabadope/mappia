package com.example.mappia;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.viewpager2.widget.ViewPager2;

import java.util.ArrayList;
import java.util.List;

public class OnboardingActivity extends AppCompatActivity {
    private static final String PREFS_NAME = "onboarding_prefs";
    private static final String KEY_ONBOARDING_COMPLETE = "onboarding_complete";

    private ViewPager2 onboardingViewPager;
    private LinearLayout layoutOnboardingIndicators;
    private Button buttonSkip, buttonNext, buttonGetStarted;
    private OnboardingAdapter onboardingAdapter;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Check if onboarding is already completed
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        if (prefs.getBoolean(KEY_ONBOARDING_COMPLETE, false)) {
            launchMain();
            return;
        }

        setContentView(R.layout.activity_onboarding);

        onboardingViewPager = findViewById(R.id.onboardingViewPager);
        layoutOnboardingIndicators = findViewById(R.id.layoutOnboardingIndicators);
        buttonSkip = findViewById(R.id.buttonOnboardingSkip);
        buttonNext = findViewById(R.id.buttonOnboardingNext);
        buttonGetStarted = findViewById(R.id.buttonOnboardingGetStarted);

        setupOnboardingItems();
        setupIndicators();
        setCurrentIndicator(0);

        onboardingViewPager.registerOnPageChangeCallback(new ViewPager2.OnPageChangeCallback() {
            @Override
            public void onPageSelected(int position) {
                super.onPageSelected(position);
                setCurrentIndicator(position);
                if (position == onboardingAdapter.getItemCount() - 1) {
                    buttonNext.setVisibility(View.GONE);
                    buttonGetStarted.setVisibility(View.VISIBLE);
                } else {
                    buttonNext.setVisibility(View.VISIBLE);
                    buttonGetStarted.setVisibility(View.GONE);
                }
            }
        });

        buttonSkip.setOnClickListener(v -> completeOnboarding());
        buttonNext.setOnClickListener(v -> {
            int nextIndex = onboardingViewPager.getCurrentItem() + 1;
            if (nextIndex < onboardingAdapter.getItemCount()) {
                onboardingViewPager.setCurrentItem(nextIndex);
            }
        });
        buttonGetStarted.setOnClickListener(v -> completeOnboarding());
    }

    private void setupOnboardingItems() {
        List<OnboardingItem> items = new ArrayList<>();
        items.add(new OnboardingItem(
                R.drawable.ic_launcher_foreground,
                "Welcome to Mappia!",
                "Order your favorite meals from local restaurants with just a few taps."
        ));
        items.add(new OnboardingItem(
                R.drawable.ic_launcher_background,
                "Fast Delivery",
                "Get your food delivered quickly and track your order in real time."
        ));
        items.add(new OnboardingItem(
                R.drawable.ic_launcher_foreground,
                "Easy Payment",
                "Pay securely with multiple payment options. Enjoy your meal!"
        ));
        onboardingAdapter = new OnboardingAdapter(items);
        onboardingViewPager.setAdapter(onboardingAdapter);
    }

    private void setupIndicators() {
        int count = onboardingAdapter.getItemCount();
        TextView[] indicators = new TextView[count];
        layoutOnboardingIndicators.removeAllViews();
        for (int i = 0; i < count; i++) {
            indicators[i] = new TextView(this);
            indicators[i].setText("●");
            indicators[i].setTextSize(18);
            indicators[i].setTextColor(ContextCompat.getColor(this, android.R.color.darker_gray));
            layoutOnboardingIndicators.addView(indicators[i]);
        }
    }

    private void setCurrentIndicator(int index) {
        int childCount = layoutOnboardingIndicators.getChildCount();
        for (int i = 0; i < childCount; i++) {
            TextView indicator = (TextView) layoutOnboardingIndicators.getChildAt(i);
            if (i == index) {
                indicator.setTextColor(ContextCompat.getColor(this, android.R.color.holo_blue_dark));
            } else {
                indicator.setTextColor(ContextCompat.getColor(this, android.R.color.darker_gray));
            }
        }
    }

    private void completeOnboarding() {
        SharedPreferences.Editor editor = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit();
        editor.putBoolean(KEY_ONBOARDING_COMPLETE, true);
        editor.apply();
        launchMain();
    }

    private void launchMain() {
        Intent intent = new Intent(this, MainActivity.class);
        startActivity(intent);
        finish();
    }
} 