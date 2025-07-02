package com.example.mappia;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.List;

public class FoodAdapter extends RecyclerView.Adapter<FoodAdapter.FoodViewHolder> {
    public interface OnAddToCartListener {
        void onAddToCart(FoodItem item);
    }

    private final List<FoodItem> foodList;
    private final OnAddToCartListener listener;

    public FoodAdapter(List<FoodItem> foodList, OnAddToCartListener listener) {
        this.foodList = foodList;
        this.listener = listener;
    }

    @NonNull
    @Override
    public FoodViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_food, parent, false);
        return new FoodViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull FoodViewHolder holder, int position) {
        holder.bind(foodList.get(position));
    }

    @Override
    public int getItemCount() {
        return foodList.size();
    }

    class FoodViewHolder extends RecyclerView.ViewHolder {
        private final ImageView imageFood;
        private final TextView textFoodName;
        private final TextView textFoodPrice;
        private final Button buttonAddToCart;

        public FoodViewHolder(@NonNull View itemView) {
            super(itemView);
            imageFood = itemView.findViewById(R.id.imageFood);
            textFoodName = itemView.findViewById(R.id.textFoodName);
            textFoodPrice = itemView.findViewById(R.id.textFoodPrice);
            buttonAddToCart = itemView.findViewById(R.id.buttonAddToCart);
        }

        void bind(final FoodItem item) {
            imageFood.setImageResource(item.getImageResId());
            textFoodName.setText(item.getName());
            textFoodPrice.setText(String.format("$%.2f", item.getPrice()));
            buttonAddToCart.setOnClickListener(v -> listener.onAddToCart(item));
        }
    }
} 